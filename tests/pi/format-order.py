"""Real Pi + gopls: format-on-write runs before the LSP diagnostics, so they describe the formatted file.

All provider replies are scripted on loopback. Pi, the extensions, gofumpt and gopls are the real ones.
Three runs of the same unformatted, non-compiling Go file:
  format then lsp  -> the diagnostic points at the formatted line
  lsp only         -> the diagnostic points at the line as written (what the formatter changes)
  lsp then format  -> the formatter ran, but the diagnostics describe the stale file (why the order matters)
"""
import json
import os
import re
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

pi, fixture_file, output = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)

SOURCE = "package main\nfunc main(){\nx:=1\n}\n"
FORMATTED = "package main\n\nfunc main() {\n\tx := 1\n}\n"


def run(name, extensions):
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-format-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    (project / "go.mod").write_text("module example.com/fixture\n\ngo 1.26\n")
    (agent / "settings.json").write_text(json.dumps({
        "lsp": fixture["settings"], "extensions": extensions,
        "retry": {"enabled": False}, "compaction": {"enabled": False}, "quietStartup": "header"}))
    requests = []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            requests.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
            first = len(requests) == 1

            def chunk(delta, finish=None):
                return {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "unit",
                        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            events = [chunk({"role": "assistant"})]
            if first:
                arguments = json.dumps({"path": "main.go", "content": SOURCE})
                events.append(chunk({"tool_calls": [{"index": 0, "id": "step-0-0", "type": "function",
                                                     "function": {"name": "write", "arguments": arguments}}]}))
            else:
                events.append(chunk({"content": "FORMAT_ORDER_COMPLETE"}))
            events.append(chunk({}, "tool_calls" if first else "stop"))
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
        'models: [{id:"unit",name:"unit",reasoning:false,input:["text"],contextWindow:200000,maxTokens:4096,'
        'cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}] });\n};\n')
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(runroot), "XDG_CACHE_HOME": str(home / "cache"),
           "XDG_CONFIG_HOME": str(home / "config"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
           "GOCACHE": str(runroot / "go-cache"), "GOMODCACHE": str(runroot / "go-mod"), "GOPATH": str(runroot / "go-path"),
           "FIXTURE_URL": f"http://127.0.0.1:{server.server_port}/v1", "TERM": "dumb", "LANG": "C.UTF-8", "SHELL": "/bin/sh"}
    args = [pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            "--no-session", "-e", str(provider), "--model", "fixture/unit", "--mode", "json", "-p", "Write the file."]
    try:
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=240)
    finally:
        server.shutdown()
    (out / f"{name}-events.jsonl").write_text(result.stdout)
    (out / f"{name}-stderr.txt").write_text(result.stderr)
    assert result.returncode == 0, (name, result.returncode, result.stderr, result.stdout[-3000:])
    assert not result.stderr.strip(), (name, result.stderr)
    assert len(requests) == 2, (name, len(requests))
    messages = [m for m in requests[1]["messages"] if m.get("role") == "tool" and m.get("tool_call_id") == "step-0-0"]
    assert len(messages) == 1, (name, requests[1])
    content = messages[0]["content"]
    text = content if isinstance(content, str) else json.dumps(content)
    (out / f"{name}-tool-result.txt").write_text(text)
    return text, (project / "main.go").read_text()


def flatten(text):
    return text.replace("\\n", "\n")


# gopls reports `declared and not used: x`; its line moves from 3 (as written) to 4 once formatted.
text, disk = run("format-then-lsp", [fixture["formatEntry"], fixture["lspEntry"]])
text = flatten(text)
assert disk == FORMATTED, disk
assert re.search(r"Formatted with gofumpt: \+\d+/-\d+ lines", text), text
assert re.search(r"main\.go:4[:\s]", text) and not re.search(r"main\.go:3[:\s]", text), text
assert text.index("Formatted with gofumpt") < text.index("LSP diagnostics"), text

text, disk = run("lsp-only", [fixture["lspEntry"]])
text = flatten(text)
assert disk == SOURCE, disk
assert "Formatted with" not in text
assert re.search(r"main\.go:3[:\s]", text), text

text, disk = run("lsp-then-format", [fixture["lspEntry"], fixture["formatEntry"]])
text = flatten(text)
assert disk == FORMATTED, disk
assert "Formatted with gofumpt" in text
assert re.search(r"main\.go:3[:\s]", text) and not re.search(r"main\.go:4[:\s]", text), text
print("PASS: format-on-write precedes LSP diagnostics in real Pi; reversed order reports stale lines", flush=True)
