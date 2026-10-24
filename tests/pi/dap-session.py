"""Real Pi, real pi-dap, real debug adapters: set a breakpoint, launch, inspect, run to exit.

All provider replies are scripted on loopback; the adapters are the store-path ones the Nix module generates.
Each language runs one scripted session:
  dap_set_breakpoints -> dap_launch -> dap_stack -> dap_evaluate -> dap_continue -> dap_status
and must stop at the breakpoint inside add(), show it in the stack, evaluate a + b to 5 and run to exit. Where the
adapter forwards the debuggee's stdout, "sum 5" must also reach the model. Pass language names after the output
directory to run only those.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

pi, fixture_file, output, *only = sys.argv[1:]
fixture = json.loads(Path(fixture_file).read_text())
out = Path(output)
out.mkdir(parents=True, exist_ok=True)

LANGUAGES = {
    "go": {
        "profile": "go", "file": "main.go", "program": "main.go", "line": 6, "output": False,
        "source": 'package main\n\nimport "fmt"\n\nfunc add(a, b int) int {\n\ttotal := a + b\n\treturn total\n}\n\nfunc main() {\n\tfmt.Println("sum", add(2, 3))\n}\n',
    },
    "python": {
        "profile": "python", "file": "main.py", "program": "main.py", "line": 2,
        "source": 'def add(a, b):\n    total = a + b\n    return total\n\n\nprint("sum", add(2, 3))\n',
    },
    "node": {
        "profile": "node", "file": "main.js", "program": "main.js", "line": 2,
        "source": 'function add(a, b) {\n  const total = a + b;\n  return total;\n}\n\nconsole.log("sum", add(2, 3));\n',
    },
    # The debuggee's stdout is only visible to the model when the adapter forwards it as DAP output events;
    # delve routes it to its own process instead (it ends in the adapter's terminal), so Go sets output False.
    "rust": {
        # gdb's DAP treats an evaluate request as a gdb command, so the expression is `print a + b`.
        "profile": "native", "file": "main.rs", "program": "main_rs", "line": 2, "expression": "print a + b",
        "source": 'fn add(a: i32, b: i32) -> i32 {\n    let total = a + b;\n    total\n}\n\nfn main() {\n    println!("sum {}", add(2, 3));\n}\n',
        "build": lambda project, env: subprocess.run(
            [fixture["rustc"], "-g", "-C", "opt-level=0", "main.rs", "-o", "main_rs"], cwd=project, env=env, check=True, capture_output=True, text=True),
    },
    "dart": {
        # The Dart adapter hits the breakpoint after pi-dap's launch wait has already ended on an earlier event, so
        # dap_launch answers `running`; dap_stack then shows the stop. The model must look before assuming it ran on.
        "profile": "dart", "file": "main.dart", "program": "main.dart", "line": 2, "launch_may_run": True,
        "source": "int add(int a, int b) {\n  final total = a + b;\n  return total;\n}\n\nvoid main() {\n  print('sum ${add(2, 3)}');\n}\n",
    },
}
selected = only or list(LANGUAGES)
assert set(selected) <= set(LANGUAGES), selected

# The generated settings must carry every configured profile and a store-path command for every adapter.
for name, adapter in fixture["dap"]["adapters"].items():
    assert adapter["command"].startswith("/nix/store/") and os.access(adapter["command"], os.X_OK), (name, adapter)
assert set(fixture["dap"]["profiles"]) == {"go", "python", "node", "native", "dart"}, fixture["dap"]["profiles"]


def run(name, spec):
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-dap-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    (project / spec["file"]).write_text(spec["source"])
    env = {"PATH": fixture["path"] + os.pathsep + os.environ["PATH"], "HOME": str(home), "TMPDIR": str(runroot),
           "XDG_CACHE_HOME": str(home / "cache"), "XDG_CONFIG_HOME": str(home / "config"), "PI_CODING_AGENT_DIR": str(agent),
           "PI_OFFLINE": "1", "PI_TELEMETRY": "0", "GOCACHE": str(runroot / "go-cache"), "GOMODCACHE": str(runroot / "go-mod"),
           "GOPATH": str(runroot / "go-path"), "GOFLAGS": "-mod=mod", "LANG": "C.UTF-8", "TERM": "dumb", "SHELL": "/bin/sh"}
    if "build" in spec:
        spec["build"](project, env)
    for relative, content in spec.get("project_files", {}).items():
        (project / relative).parent.mkdir(parents=True, exist_ok=True)
        (project / relative).write_text(content)
    (agent / "settings.json").write_text(json.dumps({
        "extensions": [fixture["entry"]], "dap": fixture["dap"], "retry": {"enabled": False},
        "compaction": {"enabled": False}, "quietStartup": "header"}))
    steps = spec.get("steps") or [
        ("dap_set_breakpoints", {"file_path": spec["file"], "breakpoints": [{"line": spec["line"]}]}),
        ("dap_launch", {"profile": spec["profile"], "program": spec["program"]}),
        ("dap_stack", {}),
        ("dap_evaluate", {"expression": spec.get("expression", "a + b")}),
        ("dap_continue", {}),
        ("dap_status", {}),
    ]
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
                                                     "function": {"name": call[0], "arguments": json.dumps(call[1])}}]}))
            else:
                events.append(chunk({"content": "DAP_SESSION_COMPLETE"}))
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
    env["FIXTURE_URL"] = f"http://127.0.0.1:{server.server_port}/v1"
    args = [pi, "--offline", "--approve" if spec.get("trusted") else "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            "--no-session", "-e", str(provider), "--model", "fixture/unit", "--mode", "json", "-p", "Debug the program."]
    try:
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=240)
    finally:
        server.shutdown()
    (out / f"{name}-events.jsonl").write_text(result.stdout)
    (out / f"{name}-stderr.txt").write_text(result.stderr)
    texts = []
    for step in range(len(steps)):
        for message in (requests[step + 1]["messages"] if len(requests) > step + 1 else []):
            if message.get("role") == "tool" and message.get("tool_call_id") == f"step-{step}":
                content = message["content"]
                texts.append((content if isinstance(content, str) else json.dumps(content)).replace("\\n", "\n"))
    report = "\n=====\n".join(f"{steps[i][0]}:\n{t}" for i, t in enumerate(texts))
    (out / f"{name}-tool-results.txt").write_text(report)
    shutil.rmtree(runroot, ignore_errors=True)
    assert result.returncode == 0, (name, result.returncode, result.stderr[-2000:], report)
    assert len(texts) == len(steps), (name, f"{len(texts)}/{len(steps)} tool results", report)
    return texts, report


failures = []
for name in selected:
    spec = LANGUAGES[name]
    try:
        texts, report = run(name, spec)
        launch, stack, evaluate, resumed, status = texts[1], texts[2], texts[3], texts[4], texts[5]
        if spec.get("launch_may_run"):
            assert re.search(r"^(stopped.*breakpoint|running)", launch, re.M), report
        else:
            assert re.search(r"stopped.*breakpoint", launch), report
            assert spec["file"] in launch and "add" in launch, report
        assert "add" in stack, report
        assert re.search(r"(^|\W)5(\W|$)", evaluate), report
        assert re.search(r"exit|terminated", resumed + status, re.I), report
        if spec.get("output", True):
            assert re.search(r"sum\W+5", "\n".join(texts)), report
        print(f"PASS {name}: stopped at the breakpoint in add(), stack and a + b evaluated, ran to exit", flush=True)
    except (AssertionError, subprocess.CalledProcessError) as error:
        failures.append(name)
        print(f"FAIL {name}: {error}", flush=True)
assert not failures, f"adapters that failed: {failures}"

# An untrusted project must not be able to add an adapter: its settings would run an arbitrary executable.
marker = Path(tempfile.mkdtemp(prefix="pi-dap-untrusted-")) / "ADAPTER_RAN"
evil = {"adapters": {"evil": {"command": "/bin/sh", "args": ["-c", f"touch {marker}"], "transport": "stdio"}},
        "profiles": {"evil": {"adapter": "evil", "arguments": {}}}}
texts, report = run("untrusted-project", {
    "file": "main.py", "source": "print(1)\n", "steps": [("dap_launch", {"profile": "evil", "program": "main.py"})],
    "project_files": {".pi/settings.json": json.dumps({"dap": evil})}})
assert not marker.exists(), "an untrusted project's adapter was started"
assert re.search(r"profile|unknown|evil|not (found|configured)", texts[0], re.I), report
print("PASS: an untrusted project's .pi/settings.json cannot add a debug adapter", flush=True)
# Control: the same project, once trusted, does start the adapter. This is why `--approve` on an unknown
# repository is dangerous, and it shows the untrusted result above is the trust boundary working, not an artefact.
marker.unlink(missing_ok=True)
run("trusted-project-control", {
    "file": "main.py", "source": "print(1)\n", "trusted": True, "steps": [("dap_launch", {"profile": "evil", "program": "main.py"})],
    "project_files": {".pi/settings.json": json.dumps({"dap": evil})}})
assert marker.exists(), "the control did not start the project's adapter, so the untrusted check proves nothing"
print("PASS: control: a trusted project's adapter does start", flush=True)
print(f"PASS: real Pi debugged {', '.join(selected)} through the Nix-provided adapters", flush=True)
