"""Persistent Python kernel behind Pi's `eval` tool. Standard library only.

Protocol, all newline-delimited JSON:
  fd 3 (host -> kernel)  {"op":"run","id":N,"code":...}  one cell
                         {"op":"result","id":K,"ok":bool,"value"|"error":...}  answer to a tool call
  fd 4 (kernel -> host)  {"op":"ready"}
                         {"op":"call","id":K,"name":...,"args":{...}}  a cell called `tool.<name>(...)`
                         {"op":"done","id":N,"ok":bool,"images":[...]}  the cell finished
A cell's printed output travels on stdout (stderr is merged into it), so it carries children's output too. Each cell
ends with the marker `\\0PIEVAL-<nonce>-<N>\\0` on stdout, which tells the host every byte of the cell has arrived.
The host interrupts a cell with SIGINT. stdin is /dev/null; the control channels are private descriptors that no
child process inherits.
"""
import ast
import base64
import builtins
import json
import linecache
import os
import signal
import sys
import traceback
import types

NONCE = sys.argv[1]
MAX_REPR = 100


def _open_channels():
    reader = os.fdopen(os.dup(3), "r", encoding="utf-8", newline="\n")
    writer = os.fdopen(os.dup(4), "w", encoding="utf-8", newline="\n")
    os.close(3)
    os.close(4)
    null = os.open(os.devnull, os.O_RDONLY)
    os.dup2(null, 0)
    os.close(null)
    os.dup2(1, 2)
    return reader, writer


def _die_with_parent():
    """An idle kernel exits when the control pipe closes, but a cell that is computing never reads it: have the kernel
    killed when Pi goes away (Linux PR_SET_PDEATHSIG; a no-op elsewhere)."""
    try:
        import ctypes
        ctypes.CDLL(None).prctl(1, signal.SIGKILL)
    except (OSError, AttributeError):
        pass


_die_with_parent()
CONTROL_IN, CONTROL_OUT = _open_channels()
sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")
signal.signal(signal.SIGINT, signal.default_int_handler)
sys.path[:] = [os.getcwd()] + [entry for entry in sys.path if entry and os.path.abspath(entry) != os.path.dirname(os.path.abspath(__file__))]


def send(message):
    CONTROL_OUT.write(json.dumps(message, ensure_ascii=False) + "\n")
    CONTROL_OUT.flush()


class ToolError(Exception):
    """A tool a cell called through `tool.<name>(...)` failed."""


_call_counter = 0


def _call(name, args):
    global _call_counter
    _call_counter += 1
    call_id = _call_counter
    send({"op": "call", "id": call_id, "name": name, "args": args})
    while True:
        line = CONTROL_IN.readline()
        if not line:
            raise SystemExit("the host closed the kernel")
        message = json.loads(line)
        if message.get("op") == "result" and message.get("id") == call_id:
            if message.get("ok"):
                return message.get("value")
            raise ToolError(message.get("error") or f"tool {name} failed")


class _Tool:
    """`tool.read(path="a.py")`, `tool["mcp__server__tool"](x=1)`: any callable tool of the session."""

    def __getattr__(self, name):
        if name.startswith("__"):
            raise AttributeError(name)
        return lambda *positional, **named: _invoke(name, positional, named)

    def __getitem__(self, name):
        return self.__getattr__(name)

    def __repr__(self):
        return "<tool: call tool.<name>(**arguments)>"


def _invoke(name, positional, named):
    if positional:
        if len(positional) != 1 or named or not isinstance(positional[0], dict):
            raise TypeError("a tool takes keyword arguments or one dict of arguments")
        arguments = positional[0]
    else:
        arguments = named
    return _call(name, arguments)


_images = []


def _sniff(raw):
    if raw.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if raw.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if raw.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if raw[:4] == b"RIFF" and raw[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("image() takes PNG, JPEG, GIF or WebP bytes, a path to one, or an image block from a tool")


def image(source):
    """Attach an image to the cell's result: a path, bytes, or an image block returned by a tool."""
    if isinstance(source, dict) and source.get("type") == "image":
        data, mime = source["data"], source["mimeType"]
    else:
        raw = bytes(source) if isinstance(source, (bytes, bytearray)) else open(os.path.expanduser(source), "rb").read()
        data, mime = base64.b64encode(raw).decode(), _sniff(raw)
    if len(data) > 12 * 1024 * 1024:
        raise ValueError("image() is limited to 12 MiB of base64")
    _images.append({"type": "image", "data": data, "mimeType": mime})


def read(path, offset=None, limit=None):
    """The raw text of a file, with no line anchors. `offset` is the first line (1-based), `limit` a line count."""
    with open(os.path.expanduser(path), encoding="utf-8", errors="replace") as handle:
        text = handle.read()
    if offset is None and limit is None:
        return text
    lines = text.splitlines(keepends=True)
    start = max((offset or 1) - 1, 0)
    return "".join(lines[start:] if limit is None else lines[start:start + limit])


def write(path, content):
    """Write a file through the session's `write` tool, so formatting and diagnostics run."""
    return _call("write", {"path": path, "content": content})


def env(key=None, value=None):
    """`env()` the environment, `env(key)` one variable, `env(key, value)` set it for this kernel and its children."""
    if key is None:
        return dict(os.environ)
    if value is None:
        return os.environ.get(key)
    os.environ[key] = str(value)
    return value


NAMESPACE = {
    "__name__": "__main__", "__builtins__": builtins,
    "tool": _Tool(), "ToolError": ToolError, "read": read, "write": write, "env": env, "image": image,
}


def state():
    """List the variables a cell defined, with their types, and the modules it imported: how to rediscover them after the context was compacted."""
    modules = []
    for name, value in NAMESPACE.items():
        if name in _HELPERS or name == "_" or name.startswith("__"):
            continue
        if isinstance(value, types.ModuleType):
            modules.append(name)
            continue
        text = repr(value)
        text = text if len(text) <= MAX_REPR else text[:MAX_REPR - 1] + "…"
        print(f"{name}: {type(value).__name__} = {text}")
    if modules:
        print("imports: " + ", ".join(modules))


NAMESPACE["state"] = state
_HELPERS = frozenset(NAMESPACE)


def _print_exception():
    kind, value, trace = sys.exc_info()
    if isinstance(value, SyntaxError):
        sys.stdout.write("".join(traceback.format_exception_only(kind, value)))
        return
    # The first frame is `run_cell` calling exec; the cell's own frames follow it.
    sys.stdout.write("".join(traceback.format_exception(kind, value, trace.tb_next if trace else None)))


def run_cell(cell_id, code):
    del _images[:]
    filename = f"<eval-{cell_id}>"
    linecache.cache[filename] = (len(code), None, code.splitlines(True), filename)
    ok = True
    try:
        tree = ast.parse(code, filename=filename, mode="exec")
        last = ast.Expression(tree.body.pop().value) if tree.body and isinstance(tree.body[-1], ast.Expr) else None
        exec(compile(tree, filename, "exec"), NAMESPACE)
        if last is not None:
            value = eval(compile(ast.fix_missing_locations(last), filename, "eval"), NAMESPACE)
            if value is not None:
                NAMESPACE["_"] = value
                print(repr(value))
    except KeyboardInterrupt:
        ok = False
        print("KeyboardInterrupt: the cell was interrupted")
    except SystemExit as exit_request:
        ok = False
        print(f"SystemExit({exit_request.code!r}): exit() ends a cell, not the kernel")
    except BaseException:
        ok = False
        _print_exception()
    finally:
        linecache.cache.pop(filename, None)
    sys.stdout.flush()
    sys.stderr.flush()
    send({"op": "done", "id": cell_id, "ok": ok, "images": list(_images)})
    os.write(1, f"\0PIEVAL-{NONCE}-{cell_id}\0".encode())


send({"op": "ready"})
while True:
    try:
        line = CONTROL_IN.readline()
        if not line:
            break
        message = json.loads(line)
        if message.get("op") == "run":
            run_cell(message["id"], message["code"])
    except KeyboardInterrupt:
        continue
