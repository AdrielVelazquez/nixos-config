"""Real Pi, real `eval` extension, real Python kernel: persistence, failure recovery, and tool re-entry.

All provider replies are scripted on loopback; Pi, the extensions, the kernel, gofumpt and gopls are the real ones.
Three scenarios, each a scripted sequence of `eval` calls whose results are read back from the provider's next request:

  kernel   eval + codemode only: variables survive separate model turns, a traceback, a timeout and a reset that
           discards them; stdout, stderr and a child process arrive in order; a kernel that was killed from inside
           reports it once and restarts; long output is truncated to a file; an image reaches the model;
           `tool.eval` is refused; codemode is declared and its description size is recorded.
  tools    eval + hashline + format-on-write + the LSP on a Go file: `write()` runs the formatter and the LSP on the
           file it wrote, `tool.read` returns the anchored text while `read()` returns the raw text, `tool.bash` works.
"""
import json
import os
import re
import struct
import subprocess
import sys
import tempfile
import threading
import zlib
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

pi, fixture_file, output = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)


def png(width=8, height=8):
    """A valid PNG: Pi's image pipeline drops one whose checksums are wrong."""
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    rows = b"".join(b"\x00" + bytes([200, 50, 50]) * width for _ in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(rows)) + chunk(b"IEND", b""))


def cell(code, **extra):
    return ("eval", {"code": code, **extra})


def run(name, extensions, files, steps, settings=None, session=None):
    """Run one scripted session; return (tool-result texts, requests, project directory, events).

    `session` names a session file to resume or create; a step runs per tool result that follows the latest prompt, so a
    resumed session's earlier results do not count.
    """
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-eval-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    for relative, content in files.items():
        (project / relative).write_bytes(content if isinstance(content, bytes) else content.encode())
    (agent / "settings.json").write_text(json.dumps({
        **(settings or {}), "extensions": extensions,
        "retry": {"enabled": False}, "compaction": {"enabled": False}, "quietStartup": "header"}))
    results, requests = [], []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            # An image a tool returned comes back as a user message; only a prompt without one starts a run.
            messages = body["messages"]
            prompt = max(i for i, message in enumerate(messages) if message["role"] == "user" and not (
                isinstance(message["content"], list) and any(part.get("type") == "image_url" for part in message["content"])))
            results[:] = [m["content"] if isinstance(m["content"], str) else "\n".join(part.get("text", "") for part in m["content"])
                          for m in messages[prompt:] if m["role"] == "tool"]
            index = len(results)
            call = steps[index](results, project) if index < len(steps) else None

            def chunk(delta, finish=None):
                return {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "unit",
                        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            events = [chunk({"role": "assistant"})]
            if call:
                events.append(chunk({"tool_calls": [{"index": 0, "id": f"{name}-step-{index}", "type": "function",
                                                     "function": {"name": call[0], "arguments": json.dumps(call[1])}}]}))
            else:
                events.append(chunk({"content": "EVAL_SESSION_COMPLETE"}))
            events.append(chunk({}, "tool_calls" if call else "stop"))
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()
            for event in events:
                self.wfile.write(("data: " + json.dumps(event) + "\n\n").encode())
            self.wfile.write(b"data: [DONE]\n\n")
            self.wfile.flush()

    server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    provider = runroot / "provider.ts"
    provider.write_text(
        'export default pi => {\n'
        'pi.registerProvider("fixture", { baseUrl: process.env.FIXTURE_URL, apiKey: "synthetic", api: "openai-completions", '
        'models: [{id:"unit",name:"unit",reasoning:false,input:["text","image"],contextWindow:200000,maxTokens:4096,'
        'cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}] });\n};\n')
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(runroot), "XDG_CACHE_HOME": str(home / "cache"),
           "XDG_CONFIG_HOME": str(home / "config"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
           "GOCACHE": str(runroot / "go-cache"), "GOMODCACHE": str(runroot / "go-mod"), "GOPATH": str(runroot / "go-path"),
           "FIXTURE_URL": f"http://127.0.0.1:{server.server_port}/v1", "TERM": "dumb", "LANG": "C.UTF-8", "SHELL": "/bin/sh"}
    args = [pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            *(["--session", str(session)] if session else ["--no-session"]), "-e", str(provider), "--model", "fixture/unit", "--mode", "json", "-p", "Run the script."]
    try:
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=330)
    finally:
        server.shutdown()
    (out / f"{name}-events.jsonl").write_text(result.stdout)
    (out / f"{name}-stderr.txt").write_text(result.stderr)
    (out / f"{name}-results.txt").write_text("\n\n=====\n".join(results))
    assert result.returncode == 0, (name, result.returncode, result.stderr, result.stdout[-3000:])
    assert not result.stderr.strip(), (name, result.stderr)
    assert len(results) == len(steps), (name, len(results), len(steps), results[-1:])
    events = [json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")]
    return results, requests, project, events


def failed_calls(events):
    """Tool call ids whose execution ended in an error, in order."""
    return [event["toolCallId"] for event in events if event.get("type") == "tool_execution_end" and event.get("isError")]


def kernel():
    steps = [
        lambda r, p: cell("import math\nrate = 3\ndef scale(x):\n    return x * rate"),
        lambda r, p: cell("scale(math.floor(2.5))"),
        lambda r, p: cell("1 / 0"),
        lambda r, p: cell("rate"),
        lambda r, p: cell("import time\ntime.sleep(60)", timeout=1),
        lambda r, p: cell("rate"),
        lambda r, p: cell('import os, sys\nprint("a", flush=True)\nos.system("echo b")\nprint("c", file=sys.stderr)'),
        lambda r, p: cell("import os, signal\nos.kill(os.getpid(), signal.SIGKILL)"),
        lambda r, p: cell("1 + 1"),
        lambda r, p: cell('for i in range(5000):\n    print("line", i)'),
        lambda r, p: cell("image('pixel.png')\nprint('shown')"),
        lambda r, p: cell('try:\n    tool.eval(code="1")\nexcept ToolError as error:\n    print("refused:", error)'),
        lambda r, p: cell("state()"),
        lambda r, p: cell('marker = "kept"'),
        lambda r, p: cell('try:\n    marker\nexcept NameError:\n    print("marker is gone")', reset=True),
        lambda r, p: cell("fresh = 5\nfresh * 2"),
    ]
    results, requests, project, events = run(
        "kernel", [fixture["evalEntry"]], {"pixel.png": png()}, steps, settings={"defaultTools": fixture["defaultTools"]})

    # Variables are defined in one model turn and used in later ones.
    assert results[0] == "(no output)", results[0]
    assert results[1] == "6", results[1]

    # A traceback is an error result that names the cell's own frame, and the namespace is intact afterwards.
    assert "ZeroDivisionError" in results[2] and "<eval-3>" in results[2] and "runner.py" not in results[2], results[2]
    assert "kernel-step-2" in failed_calls(events), failed_calls(events)
    assert results[3] == "3", results[3]

    # A timeout interrupts the cell; the variables survive it.
    assert "timed out after 1s" in results[4] and "KeyboardInterrupt" in results[4], results[4]
    assert "kernel-step-4" in failed_calls(events)
    assert results[5] == "3", results[5]

    assert results[6] == "a\nb\nc", repr(results[6])

    # A kernel killed from inside says so once; the next cell starts a fresh one without repeating the news.
    assert "kernel stopped" in results[7] and "SIGKILL" in results[7] and "kernel-step-7" in failed_calls(events), results[7]
    assert results[8] == "2", results[8]
    assert "fresh Python kernel" not in results[8]

    # Output keeps its tail; the full text is in a file the result names.
    assert "[Output truncated" in results[9] and "line 4999" in results[9], results[9][-400:]
    full = Path(re.search(r"Full output: (\S+?)\]", results[9]).group(1))
    assert len(full.read_text().splitlines()) == 5000, full

    # An image reaches the model as an image part of the following user message.
    assert results[10] == "shown", results[10]
    shown = [m for m in requests[-1]["messages"] if m["role"] == "user" and isinstance(m["content"], list)
             and any(part.get("type") == "image_url" for part in m["content"])]
    assert shown, "the image never reached the model"

    assert "tool.eval is not callable from eval" in results[11], results[11]
    # state() lists what the cells since the restart defined, and nothing from before the kill.
    assert results[12] == "i: int = 4999", results[12]

    # reset discards the variables and says so; the kernel it starts works.
    assert results[13] == "(no output)", results[13]
    assert results[14] == "The kernel was reset; every variable is gone.\nmarker is gone", results[14]
    assert results[15] == "10", results[15]

    # codemode is declared next to eval, and what it costs every request is on record.
    offered = {tool["function"]["name"]: tool["function"] for tool in requests[0]["tools"]}
    assert "eval" in offered and "codemode" in offered, sorted(offered)
    size = len(offered["codemode"]["description"])
    (out / "codemode-description-chars.txt").write_text(f"{size}\n")
    assert size < 30000, size
    print(f"PASS kernel: state across turns, traceback, timeout, stderr/child order, kill, truncation, image, reset (codemode description {size} chars)", flush=True)


def tools():
    source = "package main\nfunc main(){\nx:=1\n}\n"
    steps = [
        lambda r, p: cell(f'print(write("main.go", {source!r}))'),
        lambda r, p: cell('print(tool.read(path="main.go"))\nprint("=== raw ===")\nprint(read("main.go"))'),
        lambda r, p: cell('result = tool.bash(command="printf from-bash")\nprint(type(result).__name__, result)'),
    ]
    results, _, project, events = run(
        "tools", [fixture["formatEntry"], fixture["lspEntry"], fixture["hashlineEntry"], fixture["evalEntry"]], {}, steps,
        settings={"lsp": fixture["settings"]})
    nested = results[0].replace("\\n", "\n")
    assert "Formatted with gofumpt" in nested and "LSP diagnostics" in nested and "declared and not used" in nested, nested
    assert nested.index("Formatted with gofumpt") < nested.index("LSP diagnostics"), nested
    assert (project / "main.go").read_text() == "package main\n\nfunc main() {\n\tx := 1\n}\n", (project / "main.go").read_text()

    anchored, raw = results[1].split("=== raw ===")
    assert re.search(r"^\d+#[A-Z]{3}:package main$", anchored, re.M), anchored
    assert "#" not in raw and "package main" in raw, raw
    assert "from-bash" in results[2], results[2]
    print("PASS tools: write() is formatted and diagnosed, tool.read is anchored while read() is raw, tool.bash works", flush=True)


def resume():
    session = Path(tempfile.mkdtemp(prefix="pi-eval-session-")) / "session.jsonl"
    run("resume-first", [fixture["evalEntry"]], {}, [lambda r, p: cell("kept = 7\nkept")], session=session)
    results, _, _, _ = run("resume-second", [fixture["evalEntry"]], {}, [
        lambda r, p: cell('print("kept" in globals())'),
        lambda r, p: cell("kept = 8"),
        lambda r, p: cell("kept + 1"),
    ], session=session)
    # The session remembers `kept`; the new process does not, and the first result says so, once.
    assert results[0].startswith("A fresh Python kernel started for this Pi process; variables from earlier eval calls in this session are gone."), results[0]
    assert results[0].endswith("False"), results[0]
    assert results[2] == "9", results[2]
    print("PASS resume: a resumed session is told that its variables from the earlier process are gone", flush=True)


kernel()
tools()
resume()
print("PASS: real Pi runs the eval kernel with codemode, hashline, format-on-write and the LSP", flush=True)
