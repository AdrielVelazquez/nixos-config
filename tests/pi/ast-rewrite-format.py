"""Real Pi, real ast-grep, real ruff: an applied ast_grep_rewrite is formatted and reported.

All provider replies are scripted on loopback. The project is trusted with --approve because the rewrite tool
refuses to apply in an untrusted one. Three runs:
  preview then apply  -> the file is rewritten, then formatted, and the model is told so
  apply without preview -> refused (headless preview-first policy); the file is untouched
  no format entry     -> the rewrite lands unformatted (what the formatter changes)
"""
import json
import os
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

pi, fixture_file, output = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)

SOURCE = 'print("hi")\n'
REWRITE = {"mode": "pattern", "pattern": "print($A)", "rewrite": 'logger.info(  "[%s]"   %  $A )', "lang": "python", "path": "main.py"}
UNFORMATTED = 'logger.info(  "[%s]"   %  "hi" )'
FORMATTED = 'logger.info("[%s]" % "hi")'


def run(name, extensions, steps):
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-astfmt-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    (project / "main.py").write_text(SOURCE)
    (agent / "settings.json").write_text(json.dumps({
        "extensions": extensions, "retry": {"enabled": False}, "compaction": {"enabled": False}, "quietStartup": "header"}))
    requests = []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            requests.append(json.loads(self.rfile.read(int(self.headers["Content-Length"]))))
            index = len(requests) - 1
            call = steps[index] if index < len(steps) else None

            def chunk(delta, finish=None):
                return {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "unit",
                        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            events = [chunk({"role": "assistant"})]
            if call:
                events.append(chunk({"tool_calls": [{"index": 0, "id": f"step-{index}", "type": "function",
                                                     "function": {"name": "ast_grep_rewrite", "arguments": json.dumps(call)}}]}))
            else:
                events.append(chunk({"content": "AST_REWRITE_COMPLETE"}))
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
        'models: [{id:"unit",name:"unit",reasoning:false,input:["text"],contextWindow:200000,maxTokens:4096,'
        'cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}] });\n};\n')
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(runroot), "XDG_CACHE_HOME": str(home / "cache"),
           "XDG_CONFIG_HOME": str(home / "config"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
           "FIXTURE_URL": f"http://127.0.0.1:{server.server_port}/v1", "TERM": "dumb", "LANG": "C.UTF-8", "SHELL": "/bin/sh"}
    args = [pi, "--offline", "--approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            "--no-session", "-e", str(provider), "--model", "fixture/unit", "--mode", "json", "-p", "Rewrite the file."]
    try:
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=240)
    finally:
        server.shutdown()
    (out / f"{name}-events.jsonl").write_text(result.stdout)
    (out / f"{name}-stderr.txt").write_text(result.stderr)
    assert result.returncode == 0, (name, result.returncode, result.stderr, result.stdout[-3000:])
    assert not result.stderr.strip(), (name, result.stderr)
    assert len(requests) == len(steps) + 1, (name, len(requests))
    texts = []
    for step in range(len(steps)):
        messages = [m for m in requests[step + 1]["messages"] if m.get("role") == "tool" and m.get("tool_call_id") == f"step-{step}"]
        assert len(messages) == 1, (name, step)
        content = messages[0]["content"]
        texts.append((content if isinstance(content, str) else json.dumps(content)).replace("\\n", "\n"))
    (out / f"{name}-tool-results.txt").write_text("\n=====\n".join(texts))
    return texts, (project / "main.py").read_text()


both = [fixture["formatEntry"], *fixture["astEntries"]]

texts, disk = run("preview-then-apply", both, [{**REWRITE, "apply": False}, {**REWRITE, "apply": True}])
assert "Preview only" in texts[0] and "Formatted" not in texts[0], texts[0]
assert "Applied 1 rewrite" in texts[1], texts[1]
assert "Formatted main.py with ruff" in texts[1], texts[1]
assert FORMATTED in disk and UNFORMATTED not in disk, disk
assert 'print("hi")' not in disk, disk

texts, disk = run("apply-without-preview", both, [{**REWRITE, "apply": True}])
assert "preview" in texts[0].lower(), texts[0]
assert disk == SOURCE, disk

texts, disk = run("no-formatter", fixture["astEntries"], [{**REWRITE, "apply": False}, {**REWRITE, "apply": True}])
assert "Applied 1 rewrite" in texts[1] and "Formatted" not in texts[1], texts[1]
assert UNFORMATTED in disk, disk
print("PASS: real Pi applies ast_grep_rewrite preview-first, then formats the rewritten file and reports it", flush=True)
