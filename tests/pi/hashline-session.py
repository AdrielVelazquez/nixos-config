"""Real Pi, real hashline package: anchored read/edit/grep, and their order against format-on-write and the LSP.

All provider replies are scripted on loopback; Pi, the extensions, ripgrep, gofumpt and gopls are the real ones.
Three scenarios, each a scripted tool-call sequence whose results are read back from the provider's next request:

  mechanics   hashline only, with `rg` coming only from the Pi launcher: read -> edit round trip with fresh anchors, a stale anchor
              refused after an outside change, grep through the launcher's ripgrep, CRLF / file mode / symlink kept,
              an image still delivered, `offset`/`limit` honoured.
  children    the real generated role files launch real build, plan and explore children: the writers read and
              edit by anchor, the explorer keeps Pi's native, anchor-free output.
  interplay   format-on-write + LSP + hashline on a Go file: the edit result carries hashline's own result, then
              the formatter's note, then the LSP diagnostics, and anchors taken before the formatter ran are
              refused (the note's claim), while a fresh read edits again.
"""
import json
import os
import re
import shutil
import stat
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


ANCHOR = re.compile(r"^\s*(\d+#[A-Z]{3}):?(.*)$")


def anchor(text, needle):
    """The LINE#HASH of the first anchored line containing `needle`."""
    for line in text.splitlines():
        match = ANCHOR.match(line)
        if match and needle in match.group(2):
            return match.group(1)
    raise AssertionError(f"no anchor for {needle!r} in {text[:600]!r}")


def run(name, extensions, files, steps=None, settings=None, extra_env=None, agents=None, respond=None):
    """Run one scripted session; return (tool-result texts, last request, project directory).

    `steps` scripts one tool call per provider turn from the previous results; `respond` replaces that with a
    function of the whole request, for sessions that interleave several conversations (a parent and its children).
    """
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-hashline-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    for relative, content in files.items():
        (project / relative).parent.mkdir(parents=True, exist_ok=True)
        (project / relative).write_bytes(content if isinstance(content, bytes) else content.encode())
    (agent / "settings.json").write_text(json.dumps({
        **(settings or {}), "extensions": extensions,
        "retry": {"enabled": False}, "compaction": {"enabled": False}, "quietStartup": "header"}))
    for agent_name, text in (agents or {}).items():
        (agent / "agents").mkdir(exist_ok=True)
        (agent / "agents" / f"{agent_name}.md").write_text(text)
    if agents:
        (agent / "extensions" / "subagent").mkdir(parents=True)
        (agent / "extensions" / "subagent" / "config.json").write_text(json.dumps({
            "toolActivation": "eager", "asyncByDefault": False, "defaultSubagentContext": "fresh", "maxSubagentDepth": 2,
            "intercomBridge": {"mode": "off"}}))
    results, requests = [], []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            if respond is not None:
                call = respond(body)
                index = len(requests) - 1
            else:
                tools = [message for message in body["messages"] if message["role"] == "tool"]
                if len(tools) > len(results):
                    content = tools[-1]["content"]
                    results.append(content if isinstance(content, str) else "\n".join(part.get("text", "") for part in content))
                index = len(results)
                call = steps[index](results, project) if index < len(steps) else None

            def chunk(delta, finish=None):
                return {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "unit",
                        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            events = [chunk({"role": "assistant"})]
            if call:
                events.append(chunk({"tool_calls": [{"index": 0, "id": f"step-{index}", "type": "function",
                                                     "function": {"name": call[0], "arguments": json.dumps(call[1])}}]}))
            else:
                events.append(chunk({"content": "HASHLINE_SESSION_COMPLETE"}))
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
           "FIXTURE_URL": f"http://127.0.0.1:{server.server_port}/v1", "TERM": "dumb", "LANG": "C.UTF-8", "SHELL": "/bin/sh",
           "HASHLINE_PROVIDER": str(provider), **(extra_env or {})}
    args = [pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            "--no-session", "-e", str(provider), "--model", "fixture/unit", "--mode", "json", "-p", "Run the script."]
    try:
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=270)
    finally:
        server.shutdown()
    (out / f"{name}-events.jsonl").write_text(result.stdout)
    (out / f"{name}-stderr.txt").write_text(result.stderr)
    (out / f"{name}-results.txt").write_text("\n\n=====\n".join(results))
    assert result.returncode == 0, (name, result.returncode, result.stderr, result.stdout[-3000:])
    assert not result.stderr.strip(), (name, result.stderr)
    if steps is not None:
        assert len(results) == len(steps), (name, len(results), len(steps), results[-1:])
    return results, requests[-1], project


def mechanics():
    entry = fixture["hashlineEntry"]
    # The package looks up `rg` on PATH. Nothing on this PATH provides it; the Pi launcher's own wrapper must, so a
    # nixpkgs change that drops ripgrep from that wrapper fails here instead of silently breaking `grep`.
    assert shutil.which("rg", path=os.environ["PATH"]) is None, "the sandbox PATH already has rg; the test would prove nothing about the launcher"
    files = {
        "main.ts": "export function add(a: number, b: number) {\n  const total = a + b;\n  return total;\n}\n\nconsole.log(add(2, 3));\n",
        "crlf.txt": b"one\r\ntwo\r\nthree\r\n",
        "script.sh": "#!/bin/sh\necho one\necho two\n",
        "real.txt": "alpha\nbeta\n",
        "pixel.png": png(),
    }
    steps = [
        lambda r, p: ("read", {"path": "main.ts"}),
        lambda r, p: ("edit", {"path": "main.ts", "edits": [
            {"op": "replace", "pos": anchor(r[0], "const total"), "lines": ["  const total = a + b + 0;"]}]}),
        # The file changes behind the model's back; the anchors from the edit result are now old.
        lambda r, p: ("bash", {"command": "sed -i 's/return total;/return total + 1;/' main.ts"}),
        lambda r, p: ("edit", {"path": "main.ts", "edits": [
            {"op": "replace", "pos": anchor(r[1], "return total"), "lines": ["  return total * 2;"]}]}),
        lambda r, p: ("grep", {"pattern": "total", "path": "."}),
        lambda r, p: ("read", {"path": "crlf.txt"}),
        lambda r, p: ("edit", {"path": "crlf.txt", "edits": [{"op": "replace", "pos": anchor(r[5], "two"), "lines": ["TWO"]}]}),
        lambda r, p: ("bash", {"command": "chmod 755 script.sh && ln -s real.txt link.txt"}),
        lambda r, p: ("read", {"path": "script.sh"}),
        lambda r, p: ("edit", {"path": "script.sh", "edits": [{"op": "replace", "pos": anchor(r[8], "echo two"), "lines": ["echo 2"]}]}),
        lambda r, p: ("read", {"path": "link.txt"}),
        lambda r, p: ("edit", {"path": "link.txt", "edits": [{"op": "replace", "pos": anchor(r[10], "beta"), "lines": ["BETA"]}]}),
        lambda r, p: ("read", {"path": "pixel.png"}),
        lambda r, p: ("read", {"path": "main.ts", "offset": 2, "limit": 2}),
    ]
    results, last, project = run("mechanics", [entry], files, steps)

    assert all(ANCHOR.match(line) for line in results[0].splitlines() if line.strip()), results[0]
    assert (project / "main.ts").read_text().splitlines()[1] == "  const total = a + b + 0;", (project / "main.ts").read_text()
    assert re.search(r"\d+#[A-Z]{3}:", results[1]), "the edit result must carry fresh anchors: " + results[1]

    text = (project / "main.ts").read_text()
    assert "return total + 1;" in text and "return total * 2;" not in text, text
    assert "E_STALE_ANCHOR" in results[3], results[3]

    assert re.search(r"\d+#[A-Z]{3}:.*total", results[4]), results[4]

    assert (project / "crlf.txt").read_bytes() == b"one\r\nTWO\r\nthree\r\n", (project / "crlf.txt").read_bytes()
    assert stat.S_IMODE((project / "script.sh").stat().st_mode) == 0o755, oct((project / "script.sh").stat().st_mode)
    assert (project / "script.sh").read_text() == "#!/bin/sh\necho one\necho 2\n"
    assert (project / "link.txt").is_symlink(), "the edit replaced the symlink instead of its target"
    assert (project / "real.txt").read_text() == "alpha\nBETA\n", (project / "real.txt").read_text()

    assert "image/png" in results[12], results[12]
    delivered = [m for m in last["messages"] if m["role"] == "user" and isinstance(m["content"], list)
                 and any(part.get("type") == "image_url" for part in m["content"])]
    assert delivered, "the image never reached the model"

    window = [line for line in results[13].splitlines() if ANCHOR.match(line)]
    assert [ANCHOR.match(line).group(1).split("#")[0] for line in window] == ["2", "3"], results[13]
    print("PASS mechanics: anchored read/edit, stale refusal, grep with rg only from the Pi launcher, CRLF, mode, symlink, image, window", flush=True)


def interplay():
    hashline, fmt, lsp = fixture["hashlineEntry"], fixture["formatEntry"], fixture["lspEntry"]
    source = "package main\nfunc main(){\nx:=1\n}\n"
    files = {"go.mod": "module example.com/fixture\n\ngo 1.26\n"}
    steps = [
        lambda r, p: ("write", {"path": "main.go", "content": source}),
        lambda r, p: ("read", {"path": "main.go"}),
        # The replacement is unformatted and declares an unused variable.
        lambda r, p: ("edit", {"path": "main.go", "edits": [{"op": "replace", "pos": anchor(r[1], "x := 1"), "lines": ["y:=2"]}]}),
        # Anchors from hashline's own result were taken before the formatter ran: they must be refused.
        lambda r, p: ("edit", {"path": "main.go", "edits": [{"op": "replace", "pos": anchor(r[2], "y"), "lines": ["z:=3"]}]}),
        lambda r, p: ("read", {"path": "main.go"}),
        lambda r, p: ("edit", {"path": "main.go", "edits": [{"op": "replace", "pos": anchor(r[4], "y := 2"), "lines": ["\t_ = 2"]}]}),
    ]
    results, _, project = run("interplay", [fmt, lsp, hashline], files, steps, settings={"lsp": fixture["settings"]})
    edit = results[2].replace("\\n", "\n")
    assert re.search(r"Formatted with gofumpt: \+\d+/-\d+ lines", edit), edit
    assert "Anchors (LINE#HASH) from before this note are stale" in edit, edit
    assert "LSP diagnostics" in edit and re.search(r"declared and not used", edit), edit
    assert edit.index("Formatted with gofumpt") < edit.index("LSP diagnostics"), edit
    assert re.search(r"\d+#[A-Z]{3}:", edit), "hashline's own result is missing from the edit result: " + edit
    assert "E_STALE_ANCHOR" in results[3], results[3]
    assert "z:=3" not in (project / "main.go").read_text()
    assert (project / "main.go").read_text() == "package main\n\nfunc main() {\n\t_ = 2\n}\n", (project / "main.go").read_text()
    assert "E_STALE_ANCHOR" not in results[5], results[5]
    print("PASS interplay: hashline result, then formatter note, then LSP diagnostics; pre-format anchors refused; re-read edits", flush=True)


def flatten_content(content):
    return content if isinstance(content, str) else "\n".join(part.get("text", "") for part in content)


def children():
    """The real generated build/plan/explore role files launch real children: only the writers get hashline."""
    anchored = re.compile(r"^\s*\d+#[A-Z]{3}:", re.M)

    def role(name, tools):
        # The generated text, with the model and tool list swapped for what a loopback fixture can serve; the
        # `extensions` and `subagentOnlyExtensions` lines are kept exactly as Nix generated them.
        text = fixture["roles"][name]
        for key, value in (("model", "fixture/unit"), ("thinking", "off"), ("tools", tools)):
            text, count = re.subn(rf"^{key}: .*$", f"{key}: {value}", text, flags=re.M)
            assert count == 1, (name, key, text)
        return text

    agents = {"build": role("build", "read, grep, edit"), "plan": role("plan", "read, grep"),
              "explore": role("explore", "read, grep")}
    order = ["build", "plan", "explore"]
    seen = {}

    def respond(body):
        names = {tool["function"]["name"]: tool["function"] for tool in body.get("tools", [])}
        results = [flatten_content(m["content"]) for m in body["messages"] if m["role"] == "tool"]
        if "subagent" in names:
            if len(results) < len(order):
                kind = order[len(results)]
                return ("subagent", {"agent": kind, "task": f"CHILD_{kind.upper()}", "async": False})
            return None
        first_user = json.dumps(next(m for m in body["messages"] if m["role"] == "user")["content"])
        kind = next(candidate for candidate in order if f"CHILD_{candidate.upper()}" in first_user)
        seen[kind] = {"tools": names, "results": results}
        if not results:
            return ("read", {"path": "main.ts"})
        if kind == "build" and len(results) == 1:
            return ("edit", {"path": "main.ts", "edits": [
                {"op": "replace", "pos": anchor(results[0], "const total"), "lines": ["  const total = a + b + 0;"]}]})
        return None

    files = {"main.ts": "export function add(a: number, b: number) {\n  const total = a + b;\n  return total;\n}\n"}
    # The parent does not load hashline, so a child that has it got it from its own role file.
    _, _, project = run("children", [fixture["subagentsEntry"], fixture["childHostEntry"]], files, agents=agents, respond=respond)
    assert set(seen) == set(order), seen.keys()
    edit_schema = json.dumps(seen["build"]["tools"]["edit"]["parameters"])
    assert '"op"' in edit_schema and "oldText" not in edit_schema, "the build child has the native edit: " + edit_schema
    assert anchored.search(seen["build"]["results"][0]) and anchored.search(seen["plan"]["results"][0]), seen
    assert "E_" not in seen["build"]["results"][1], seen["build"]["results"][1]
    assert (project / "main.ts").read_text().splitlines()[1] == "  const total = a + b + 0;", (project / "main.ts").read_text()
    assert "edit" not in seen["explore"]["tools"], seen["explore"]["tools"].keys()
    assert "const total" in seen["explore"]["results"][0] and not anchored.search(seen["explore"]["results"][0]), seen["explore"]
    print("PASS children: build and plan read and edit by anchor, explore stays native", flush=True)


mechanics()
interplay()
children()
print("PASS: real Pi runs the pinned hashline package alongside format-on-write and the LSP", flush=True)
