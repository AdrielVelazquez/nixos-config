"""Real Pi + Go/TS acceptance. All provider replies are scripted on loopback.

No mocks replace Pi, the LSP extension or either language server. The delayed
scenario only holds the real gopls publishDiagnostics frames for nine seconds.
"""
import codecs
import copy
import fcntl
import json
import os
from pathlib import Path
import pty
import re
import select
import signal
import struct
import subprocess
import sys
import tempfile
import termios
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

pi, fixture_file, delay_proxy, output = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)
root = Path(tempfile.mkdtemp(prefix="pi-lsp-"))
settings = fixture["settings"]
expected = {"gopls", "typescript", "nixd", "basedpyright", "ruff", "pyrefly", "bash", "rust", "lua", "marksman", "json", "terraform", "zls"}
assert set(settings["servers"]) == expected, settings
assert "gopls" not in fixture["disabledServers"]
assert fixture["missingExecutableRejected"]
for name, server in settings["servers"].items():
    assert server["command"].startswith("/nix/store/") and os.access(server["command"], os.X_OK), (name, server)
assert "typescript-5." in settings["servers"]["typescript"]["initializationOptions"]["tsserver"]["path"]
assert settings["servers"]["typescript"]["initializationOptions"]["disableAutomaticTypingAcquisition"]
assert settings["servers"]["gopls"]["environment"]["GOTELEMETRY"] == "off"
assert settings["servers"]["gopls"]["environment"]["GOTOOLCHAIN"] == "local"
assert settings["servers"]["gopls"]["settings"]["gopls"]["analyses"]["unusedparams"]
assert settings["servers"]["rust"]["environment"].get("CARGO_NET_OFFLINE") == "true"
assert settings["servers"]["json"]["initializationOptions"].get("handledSchemaProtocols") == ["file"]
assert settings["servers"]["json"]["settings"].get("json", {}).get("validate", {}).get("enable") is True
assert {extension for mapping in settings["servers"]["gopls"]["languages"] for extension in mapping["extensions"]} == {".go", ".mod", ".sum"}
assert settings["servers"]["basedpyright"]["settings"]["basedpyright"]["analysis"]["useLibraryCodeForTypes"]
GO = 'package main\n\nfunc greet(name string) string { return "Hello " + name }\n\nfunc main() {\n    var value int = 42\n    _ = value\n    _ = greet("lab")\n}\n'
TS = 'export function greet(name: string): string { return "Hello " + name; }\n\nconst count: number = 42;\nconsole.log(greet("lab"), count);\n'

def call(name, **arguments):
    return {"name": name, "arguments": arguments}

def run(name, steps, *, delayed=False, missing=False, terminal=False):
    runroot = root / name
    agent, project, home = [runroot / part for part in ["agent", "project", "home"]]
    for directory in [agent, project, home]:
        directory.mkdir(parents=True)
    for path, text in {"go.mod": "module example.com/fixture\n\ngo 1.26\n", "main.go": GO, "main.ts": TS,
                       "package.json": '{"private":true}', "tsconfig.json": '{"compilerOptions":{"strict":true,"target":"ES2020","module":"commonjs","noEmit":true},"include":["main.ts"]}'}.items():
        (project / path).write_text(text)
    config = copy.deepcopy(settings)
    config["servers"] = {key: value for key, value in config["servers"].items() if key in ["gopls", "typescript"]}
    if delayed:
        go = config["servers"]["gopls"]
        go["args"] = [delay_proxy, go["command"], *go["args"]]
        go["command"] = fixture["node"]
        go["environment"]["LSP_DELAY_LOG"] = str(runroot / "frames.jsonl")
    if missing:
        config["servers"]["gopls"]["command"] = str(runroot / "missing-gopls")
    trusted_settings = runroot / "managed-settings.json"
    trusted_settings.write_text(json.dumps({"lsp": config, "extensions": [fixture["entry"]], "retry": {"enabled": False}, "compaction": {"enabled": False}, "quietStartup": "header"}))
    trusted_settings.chmod(0o444)
    (agent / "settings.json").symlink_to(trusted_settings)
    # A real project config attempts to start executable code despite --no-approve.
    (project / ".pi").mkdir()
    marker = runroot / "UNTRUSTED_SERVER_RAN"
    (project / ".pi/settings.json").write_text(json.dumps({"lsp": {"servers": {"evil": {
        "command": fixture["node"], "args": ["-e", f"require('fs').writeFileSync({json.dumps(str(marker))},'ran')"],
        "languages": [{"extensions": [".go"], "languageId": "go"}], "rootMarkers": [], "requireRootMarker": False}}}}))
    requests = []
    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass
        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            index = len(requests) - 1
            calls = steps[index] if index < len(steps) else []
            def chunk(delta, finish=None):
                return {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "unit", "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            events = [chunk({"role": "assistant"})]
            for number, tool in enumerate(calls):
                events.append(chunk({"tool_calls": [{"index": number, "id": f"step-{index}-{number}", "type": "function", "function": {"name": tool["name"], "arguments": json.dumps(tool["arguments"])}}]}))
            if not calls:
                events.append(chunk({"content": "LSP_ACCEPTANCE_COMPLETE"}))
            events.append(chunk({}, "tool_calls" if calls else "stop"))
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
    provider.write_text('import { writeFileSync } from "node:fs";\nexport default pi => {\n'
        'pi.on("session_start", (_,ctx) => writeFileSync(process.env.TRUST_LOG, JSON.stringify(ctx.isProjectTrusted())));\n'
        'pi.registerProvider("fixture", { baseUrl: process.env.FIXTURE_URL, apiKey: "synthetic", api: "openai-completions", models: [{id:"unit",name:"unit",reasoning:false,input:["text"],contextWindow:200000,maxTokens:4096,cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}] });\n};\n')
    env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(runroot), "XDG_CACHE_HOME": str(home / "cache"),
           "XDG_CONFIG_HOME": str(home / "config"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
           "GOCACHE": str(runroot / "go-cache"), "GOMODCACHE": str(runroot / "go-mod"), "GOPATH": str(runroot / "go-path"),
           "FIXTURE_URL": f"http://127.0.0.1:{server.server_port}/v1", "TRUST_LOG": str(runroot / "trust.json"),
           "TERM": "xterm-256color", "COLORTERM": "truecolor", "LANG": "C.UTF-8", "SHELL": "/bin/sh"}
    args = [pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp", "--no-session", "-e", str(provider), "--model", "fixture/unit"]
    try:
        if terminal:
            raw = run_terminal(args, project, env, out / "lsp-status.png")
        else:
            result = subprocess.run([*args, "--mode", "json", "-p", "Exercise the scripted tools."], cwd=project, env=env, capture_output=True, text=True, timeout=300)
            (out / f"{name}-stderr.txt").write_text(result.stderr)
            (out / f"{name}-events.jsonl").write_text(result.stdout)
            assert result.returncode == 0, (name, result.returncode, result.stderr, result.stdout[-4000:])
            assert not result.stderr.strip(), (name, result.stderr)
            raw = result.stdout
    finally:
        server.shutdown()
    (out / f"{name}-requests.json").write_text(json.dumps(requests, indent=2))
    assert len(requests) == len(steps) + 1, (name, len(requests), raw[-4000:])
    assert json.loads((runroot / "trust.json").read_text()) is False
    assert not marker.exists(), "untrusted project added a server"
    assert (agent / "settings.json").is_symlink()
    assert "welcome" not in (project / "main.ts").read_text(), "rename preview unexpectedly mutated the project"
    print(f"PASS {name}: {len(requests)} real model requests; untrusted config rejected; managed symlink intact", flush=True)
    return requests, runroot

def tool_result(requests, step, number=0):
    # Inspect ONLY the immediately following request, not the final transcript.
    tool_id = f"step-{step}-{number}"
    messages = [message for message in requests[step + 1]["messages"] if message.get("role") == "tool" and message.get("tool_call_id") == tool_id]
    assert len(messages) == 1, (tool_id, requests[step + 1])
    content = messages[0]["content"]
    return content if isinstance(content, str) else json.dumps(content)

def run_terminal(args, project, env, image_path):
    import pyte
    from PIL import Image, ImageDraw, ImageFont
    class Screen(pyte.Screen):
        def write_process_input(self, text):
            os.write(master, text.encode())
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 40, 120, 0, 0))
    child = subprocess.Popen(args, stdin=slave, stdout=slave, stderr=slave, cwd=project, env=env, start_new_session=True)
    os.close(slave)
    screen = Screen(120, 40)
    stream = pyte.Stream(screen)
    decoder = codecs.getincrementaldecoder("utf8")("replace")
    raw, sent = bytearray(), False
    deadline = time.monotonic() + 180
    try:
        while time.monotonic() < deadline:
            if select.select([master], [], [], 0.1)[0]:
                data = os.read(master, 65536)
                raw.extend(data)
                stream.feed(decoder.decode(data))
                for match in re.finditer(rb'\x1b\](10|11);\?(\x07|\x1b\\)', data):
                    os.write(master, b'\x1b]' + match[1] + b';rgb:0000/0000/0000' + match[2])
            visible = "\n".join(screen.display)
            if not sent and "LSP 2 configured" in visible:
                os.write(master, b"Exercise the scripted tools.")
                time.sleep(0.1)
                os.write(master, b"\r")
                sent = True
            if "LSP_ACCEPTANCE_COMPLETE" in visible and "LSP gopls" in visible:
                # Allow the agent_end status refresh to paint.
                if select.select([master], [], [], 0.4)[0]:
                    data = os.read(master, 65536); raw.extend(data); stream.feed(decoder.decode(data))
                break
            assert child.poll() is None, raw.decode(errors="replace")[-4000:]
        else:
            raise AssertionError("PTY timed out: " + visible)
        assert "LSP gopls ● · typescript ●" in "\n".join(screen.display), visible
        assert "Extension errors" not in raw.decode(errors="replace")
        font = ImageFont.truetype(os.environ["PI_UI_FONT"], 14)
        width, height = 9, 18
        image = Image.new("RGB", (120 * width + 20, 40 * height + 20), "#101010")
        draw = ImageDraw.Draw(image)
        for y, row in enumerate(screen.display):
            draw.text((10, 10 + y * height), row, font=font, fill="#d8dee9")
        image.save(image_path)
        image_path.with_suffix(".txt").write_text("\n".join(screen.display))
        return raw.decode(errors="replace")
    finally:
        image_path.with_suffix(".ansi").write_bytes(raw)
        image_path.with_suffix(".txt").write_text("\n".join(screen.display))
        if child.poll() is None:
            os.write(master, b"/quit\r")
            shutdown_deadline = time.monotonic() + 5
            while child.poll() is None and time.monotonic() < shutdown_deadline:
                if select.select([master], [], [], 0.1)[0]:
                    try:
                        os.read(master, 65536)
                    except OSError:
                        break
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGKILL)
                child.wait(timeout=5)
        os.close(master)

normal = [
    [call("write", path="main.go", content=GO.replace("int = 42", 'int = "wrong"'))],
    [call("edit", path="main.ts", edits=[{"oldText": "number = 42", "newText": 'number = "wrong"'}])],
    [call("lsp_goto_definition", file_path="main.go", line=8, character=9),
     call("lsp_find_references", file_path="main.ts", line=1, character=17),
     call("lsp_hover", file_path="main.ts", line=1, character=17),
     call("lsp_rename", file_path="main.ts", line=1, character=17, new_name="welcome")],
    [call("write", path="main.go", content=GO)],
    [call("edit", path="main.ts", edits=[{"oldText": 'number = "wrong"', "newText": "number = 42"}])],
    [call("lsp_status", all=True)],
]
requests, _ = run("real-servers", normal)
assert 'cannot use "wrong"' in tool_result(requests, 0)
assert "not assignable to type 'number'" in tool_result(requests, 1)
assert "main.go:3:6" in tool_result(requests, 2, 0)
references = tool_result(requests, 2, 1)
assert "1:17" in references and "4:13" in references, references
assert "function greet(name: string): string" in tool_result(requests, 2, 2)
preview = tool_result(requests, 2, 3)
assert "Workspace Edit Preview" in preview and "function welcome" in preview and 'console.log(welcome("lab")' in preview, preview
for step in [3, 4]:
    assert "LSP diagnostics: no diagnostics" in tool_result(requests, step), tool_result(requests, step)
assert "evil" not in tool_result(requests, 5)
requests, runroot = run("delayed-diagnostics", [normal[0], normal[3]], delayed=True)
assert 'cannot use "wrong"' in tool_result(requests, 0)
assert "LSP diagnostics: no diagnostics" in tool_result(requests, 1)
assert 'cannot use "wrong"' not in tool_result(requests, 1)
frames = [json.loads(line) for line in (runroot / "frames.jsonl").read_text().splitlines()]
assert any(frame["params"]["diagnostics"] for frame in frames)
assert any(not frame["params"]["diagnostics"] for frame in frames)
requests, _ = run("missing-binary", [normal[0], [call("lsp_diagnostics", file_path="main.go")]], missing=True)
failure = tool_result(requests, 0)
assert re.search(r"unavailable|failed|not available", failure, re.I), failure
specific = tool_result(requests, 1)
assert "server gopls" in specific and "process failed to start" in specific and "stderr" in specific, specific
run("footer", normal, terminal=True)
print("PASS: Go and TypeScript NEXT-request errors, clean repairs, navigation, nine-second freshness, missing executable, untrusted config, headless and footer smoke", flush=True)
