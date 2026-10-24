"""Real Pi with the managed `defaultTools`: the native discovery tools, and the `todo` tool.

All provider replies are scripted on loopback; Pi and its extensions are the real ones, and the tool selection is what
the Nix configuration generates (`defaultTools`). Scenarios:

  discovery  `find` and `ls` are declared to the model and answer from the real tree.
  todo       the list is kept across model turns, refuses what cannot apply, and a second Pi process that resumes the
             session finds the list the first one left.
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


def call(name, **arguments):
    return (name, arguments)


def run(name, extensions, files, steps, session=None):
    """Run one scripted session; return (tool-result texts, requests, project directory, events).

    A step runs per tool result that follows the latest prompt, so a resumed session's earlier results do not count.
    """
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-tools-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    for relative, content in files.items():
        (project / relative).parent.mkdir(parents=True, exist_ok=True)
        (project / relative).write_text(content)
    (agent / "settings.json").write_text(json.dumps({
        "defaultTools": fixture["defaultTools"], "extensions": extensions,
        "retry": {"enabled": False}, "compaction": {"enabled": False}, "quietStartup": "header"}))
    results, requests = [], []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            messages = body["messages"]
            prompt = max(i for i, message in enumerate(messages) if message["role"] == "user")
            results[:] = [m["content"] if isinstance(m["content"], str) else "\n".join(part.get("text", "") for part in m["content"])
                          for m in messages[prompt:] if m["role"] == "tool"]
            index = len(results)
            step = steps[index](results, project) if index < len(steps) else None

            def chunk(delta, finish=None):
                return {"id": "fixture", "object": "chat.completion.chunk", "created": 1, "model": "unit",
                        "choices": [{"index": 0, "delta": delta, "finish_reason": finish}]}
            events = [chunk({"role": "assistant"})]
            if step:
                events.append(chunk({"tool_calls": [{"index": 0, "id": f"{name}-step-{index}", "type": "function",
                                                     "function": {"name": step[0], "arguments": json.dumps(step[1])}}]}))
            else:
                events.append(chunk({"content": "TOOLS_SESSION_COMPLETE"}))
            events.append(chunk({}, "tool_calls" if step else "stop"))
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
    args = [pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
            *(["--session", str(session)] if session else ["--no-session"]),
            "-e", str(provider), "--model", "fixture/unit", "--mode", "json", "-p", "Run the script."]
    try:
        result = subprocess.run(args, cwd=project, env=env, capture_output=True, text=True, timeout=200)
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


def discovery():
    files = {"src/a.ts": "export const a = 1;\n", "src/b.ts": "export const b = 2;\n", "README.md": "# fixture\n"}
    steps = [
        lambda r, p: call("find", pattern="*.ts"),
        lambda r, p: call("ls", path="src"),
    ]
    results, requests, _, _ = run("discovery", [], files, steps)
    offered = {tool["function"]["name"] for tool in requests[0]["tools"]}
    assert {"find", "ls"} <= offered, sorted(offered)
    assert "src/a.ts" in results[0] and "src/b.ts" in results[0] and "README.md" not in results[0], results[0]
    assert "a.ts" in results[1] and "b.ts" in results[1], results[1]
    print("PASS discovery: find and ls are declared by the managed defaultTools and answer from the real tree", flush=True)


def failed_calls(events):
    """Tool call ids whose execution ended in an error."""
    return [event["toolCallId"] for event in events if event.get("type") == "tool_execution_end" and event.get("isError")]


def todo():
    entry = fixture["todoEntry"]
    session = Path(tempfile.mkdtemp(prefix="pi-todo-session-")) / "session.jsonl"
    first_steps = [
        lambda r, p: call("todo", op="init", items=["write the test", "implement it", "document it"]),
        lambda r, p: call("todo", op="done", id=1),
        lambda r, p: call("todo", op="done", id=9),
        lambda r, p: call("todo", op="block", id=2),
        lambda r, p: call("todo", op="block", id=2, reason="needs the API key"),
        lambda r, p: call("todo", op="view"),
    ]
    results, requests, _, events = run("todo-first", [entry], {}, first_steps, session=session)
    assert "todo" in {tool["function"]["name"] for tool in requests[0]["tools"]}
    assert results[0] == "Todos: 0/3 done\n[>] #1 write the test\n[ ] #2 implement it\n[ ] #3 document it", results[0]
    assert results[1] == "Todos: 1/3 done\n[x] #1 write the test\n[>] #2 implement it\n[ ] #3 document it", results[1]
    # A request that cannot apply is a failed result, and the list is as it was.
    assert "Todo #9 does not exist" in results[2] and "todo-first-step-2" in failed_calls(events), results[2]
    assert "needs a `reason`" in results[3] and "todo-first-step-3" in failed_calls(events), results[3]
    assert results[4] == "Todos: 1/3 done\n[x] #1 write the test\n[!] #2 implement it (blocked: needs the API key)\n[>] #3 document it", results[4]
    assert results[5] == results[4], results[5]

    # A new process resumes the session: the list comes back from the earlier results, and work goes on from it.
    resumed, _, _, _ = run("todo-second", [entry], {}, [
        lambda r, p: call("todo", op="view"),
        lambda r, p: call("todo", op="unblock", id=2),
    ], session=session)
    assert resumed[0] == results[4], resumed[0]
    assert resumed[1] == "Todos: 1/3 done\n[x] #1 write the test\n[ ] #2 implement it\n[>] #3 document it", resumed[1]
    print("PASS todo: a list kept across turns and processes, impossible requests refused, blocked tasks hand over", flush=True)


discovery()
todo()
print("PASS: real Pi with the managed tool selection", flush=True)
