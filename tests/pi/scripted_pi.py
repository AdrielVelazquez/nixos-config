"""Run the real Pi against a scripted OpenAI-compatible provider on loopback: the shared harness of the Pi session checks.

    from scripted_pi import call, run

Pi and the extensions under test are the real ones; only the model is scripted. `steps` is a list with one callable per
tool call the model makes (each receives the tool results so far and the project directory and returns `call(name,
**arguments)`); when the steps run out the model answers with plain text and the run ends.
"""

import json
import os
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace


def call(name, **arguments):
    return (name, arguments)


def run(
    pi,
    name,
    extensions,
    files,
    steps,
    *,
    settings=None,
    session=None,
    path=None,
    env=None,
    prompt="Run the script.",
    out=None,
    allow_stderr=False,
    timeout=200,
    mode="json",
    before=None,
):
    """Run one scripted session and return what happened.

    The result has `results` (tool result texts after the latest prompt), `requests` (every provider request body),
    `project` (the working directory), `events` (JSON-mode events), `stdout` and `stderr`.
    `path` replaces the directories in PATH; `env` adds environment variables; `settings` is merged into settings.json;
    `before(project, agent)` runs before Pi starts, for fixtures that need the paths.
    """
    runroot = Path(tempfile.mkdtemp(prefix=f"pi-session-{name}-"))
    home, agent, project = runroot / "home", runroot / "agent", runroot / "project"
    for directory in (home, agent, project):
        directory.mkdir()
    for relative, content in files.items():
        (project / relative).parent.mkdir(parents=True, exist_ok=True)
        (project / relative).write_text(content)
    config = {
        "extensions": extensions,
        "retry": {"enabled": False},
        "compaction": {"enabled": False},
        "quietStartup": "header",
    }
    config.update(settings or {})
    (agent / "settings.json").write_text(json.dumps(config))
    if before:
        before(project, agent)
    results, requests = [], []

    class Provider(BaseHTTPRequestHandler):
        def log_message(self, *_):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            requests.append(body)
            messages = body["messages"]
            latest = max(
                i for i, message in enumerate(messages) if message["role"] == "user"
            )
            results[:] = [
                m["content"]
                if isinstance(m["content"], str)
                else "\n".join(part.get("text", "") for part in m["content"])
                for m in messages[latest:]
                if m["role"] == "tool"
            ]
            index = len(results)
            step = steps[index](results, project) if index < len(steps) else None

            def chunk(delta, finish=None):
                return {
                    "id": "fixture",
                    "object": "chat.completion.chunk",
                    "created": 1,
                    "model": "unit",
                    "choices": [{"index": 0, "delta": delta, "finish_reason": finish}],
                }

            events = [chunk({"role": "assistant"})]
            if step:
                events.append(
                    chunk(
                        {
                            "tool_calls": [
                                {
                                    "index": 0,
                                    "id": f"{name}-step-{index}",
                                    "type": "function",
                                    "function": {
                                        "name": step[0],
                                        "arguments": json.dumps(step[1]),
                                    },
                                }
                            ]
                        }
                    )
                )
            else:
                events.append(chunk({"content": "SESSION_COMPLETE"}))
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
        "export default pi => {\n"
        'pi.registerProvider("fixture", { baseUrl: process.env.FIXTURE_URL, apiKey: "synthetic", api: "openai-completions", '
        'models: [{id:"unit",name:"unit",reasoning:false,input:["text"],contextWindow:200000,maxTokens:4096,'
        "cost:{input:0,output:0,cacheRead:0,cacheWrite:0}}] });\n};\n"
    )
    environment = {
        "PATH": os.pathsep.join(path) if path is not None else os.environ["PATH"],
        "HOME": str(home),
        "TMPDIR": str(runroot),
        "XDG_CACHE_HOME": str(home / "cache"),
        "XDG_CONFIG_HOME": str(home / "config"),
        "XDG_DATA_HOME": str(home / "data"),
        "XDG_STATE_HOME": str(home / "state"),
        "PI_CODING_AGENT_DIR": str(agent),
        "PI_OFFLINE": "1",
        "PI_TELEMETRY": "0",
        "FIXTURE_URL": f"http://127.0.0.1:{server.server_port}/v1",
        "TERM": "dumb",
        "LANG": "C.UTF-8",
        "SHELL": "/bin/sh",
        "GIT_AUTHOR_NAME": "t",
        "GIT_AUTHOR_EMAIL": "t@t",
        "GIT_COMMITTER_NAME": "t",
        "GIT_COMMITTER_EMAIL": "t@t",
    }
    environment.update(env or {})
    args = [
        pi,
        "--offline",
        "--no-approve",
        "--no-context-files",
        "--no-skills",
        "--no-prompt-templates",
        "--no-mcp",
        *(["--session", str(session)] if session else ["--no-session"]),
        "-e",
        str(provider),
        "--model",
        "fixture/unit",
        "--mode",
        mode,
        "-p",
        prompt,
    ]
    try:
        result = subprocess.run(
            args,
            cwd=project,
            env=environment,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    finally:
        server.shutdown()
    if out:
        out = Path(out)
        out.mkdir(parents=True, exist_ok=True)
        (out / f"{name}-events.jsonl").write_text(result.stdout)
        (out / f"{name}-stderr.txt").write_text(result.stderr)
        (out / f"{name}-results.txt").write_text("\n\n=====\n".join(results))
    assert result.returncode == 0, (
        name,
        result.returncode,
        result.stderr,
        result.stdout[-3000:],
    )
    if not allow_stderr:
        assert not result.stderr.strip(), (name, result.stderr)
    assert len(results) == len(steps), (name, len(results), len(steps), results[-1:])
    events = [
        json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")
    ]
    return SimpleNamespace(
        results=results,
        requests=requests,
        project=project,
        agent=agent,
        events=events,
        stdout=result.stdout,
        stderr=result.stderr,
    )
