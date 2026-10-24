"""Run the real Pi against a scripted OpenAI-compatible provider on loopback: the shared harness of the Pi session checks.

    from scripted_pi import call, run, Rpc

Pi and the extensions under test are the real ones; only the model is scripted. `steps` is a list with one callable per
tool call the model makes (each receives the tool results so far and the project directory and returns `call(name,
**arguments)`); when the steps run out the model answers with plain text and the run ends.

`run` drives one prompt through print mode and returns what happened. `Rpc` keeps Pi running in RPC mode, so a check can
send several prompts and slash commands and answer the dialogs an extension opens.
"""

import json
import os
import queue
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from types import SimpleNamespace


def call(name, **arguments):
    return (name, arguments)


class Scripted:
    """A loopback provider that answers each request from `steps`, which a check may replace between prompts."""

    def __init__(self, steps, name, project):
        self.steps, self.name, self.project = steps, name, project
        self.results, self.requests = [], []
        scripted = self

        class Provider(BaseHTTPRequestHandler):
            def log_message(self, *_):
                pass

            def do_POST(self):
                body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
                scripted.requests.append(body)
                messages = body["messages"]
                latest = max(
                    i for i, message in enumerate(messages) if message["role"] == "user"
                )
                scripted.results[:] = [
                    m["content"]
                    if isinstance(m["content"], str)
                    else "\n".join(part.get("text", "") for part in m["content"])
                    for m in messages[latest:]
                    if m["role"] == "tool"
                ]
                index = len(scripted.results)
                step = (
                    scripted.steps[index](scripted.results, project)
                    if index < len(scripted.steps)
                    else None
                )

                def chunk(delta, finish=None):
                    return {
                        "id": "fixture",
                        "object": "chat.completion.chunk",
                        "created": 1,
                        "model": "unit",
                        "choices": [
                            {"index": 0, "delta": delta, "finish_reason": finish}
                        ],
                    }

                events = [chunk({"role": "assistant"})]
                if step:
                    call_id = f"{name}-step-{index}-{len(scripted.requests)}"
                    events.append(
                        chunk(
                            {
                                "tool_calls": [
                                    {
                                        "index": 0,
                                        "id": call_id,
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

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Provider)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    @property
    def url(self):
        return f"http://127.0.0.1:{self.server.server_port}/v1"

    def stop(self):
        self.server.shutdown()


def prepare(name, extensions, files, settings, before):
    """Create the throwaway home, agent directory and project of one session."""
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
    return runroot, home, agent, project


def launch(pi, runroot, home, agent, scripted, session, path, env, mode_args):
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
        "FIXTURE_URL": scripted.url,
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
        pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates", "--no-mcp",
        *(["--session", str(session)] if session else ["--no-session"]),
        "-e", str(provider), "--model", "fixture/unit", *mode_args,
    ]  # fmt: skip
    return args, environment


def run(pi, name, extensions, files, steps, *, settings=None, session=None, path=None, env=None, prompt="Run the script.",
        out=None, allow_stderr=False, timeout=200, mode="json", before=None):  # fmt: skip
    """Run one scripted prompt through print mode and return what happened.

    The result has `results` (tool result texts after the latest prompt), `requests` (every provider request body),
    `project`, `agent`, `events` (JSON-mode events), `stdout` and `stderr`.
    `path` replaces the directories in PATH; `env` adds environment variables; `settings` is merged into settings.json;
    `before(project, agent)` runs before Pi starts, for fixtures that need the paths.
    """
    runroot, home, agent, project = prepare(name, extensions, files, settings, before)
    scripted = Scripted(steps, name, project)
    args, environment = launch(
        pi,
        runroot,
        home,
        agent,
        scripted,
        session,
        path,
        env,
        ["--mode", mode, "-p", prompt],
    )
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
        scripted.stop()
    if out:
        out = Path(out)
        out.mkdir(parents=True, exist_ok=True)
        (out / f"{name}-events.jsonl").write_text(result.stdout)
        (out / f"{name}-stderr.txt").write_text(result.stderr)
        (out / f"{name}-results.txt").write_text("\n\n=====\n".join(scripted.results))
    assert result.returncode == 0, (
        name,
        result.returncode,
        result.stderr,
        result.stdout[-3000:],
    )
    if not allow_stderr:
        assert not result.stderr.strip(), (name, result.stderr)
    assert len(scripted.results) == len(steps), (
        name,
        len(scripted.results),
        len(steps),
        scripted.results[-1:],
    )
    events = [
        json.loads(line) for line in result.stdout.splitlines() if line.startswith("{")
    ]
    return SimpleNamespace(
        results=scripted.results,
        requests=scripted.requests,
        project=project,
        agent=agent,
        events=events,
        stdout=result.stdout,
        stderr=result.stderr,
    )


class Rpc:
    """Pi in RPC mode with a scripted model: send prompts and slash commands, answer the dialogs extensions open.

    `answer(request)` decides each dialog: return `True`/`False` for a confirm, an option string for a select, or `None`
    to cancel. `notifications` collects every `notify` an extension sent, `statuses` the latest status per key.
    """

    def __init__(
        self,
        pi,
        name,
        extensions,
        files,
        *,
        settings=None,
        session=None,
        path=None,
        env=None,
        before=None,
        answer=None,
    ):
        self.runroot, home, self.agent, self.project = prepare(
            name, extensions, files, settings, before
        )
        self.scripted = Scripted([], name, self.project)
        self.answer = answer or (
            lambda request: (
                True
                if request["method"] == "confirm"
                else (request.get("options") or [None])[0]
            )
        )
        self.records, self.notifications, self.dialogs, self.statuses = [], [], [], {}
        self.stderr = []
        self.lines = queue.Queue()
        args, environment = launch(
            pi,
            self.runroot,
            home,
            self.agent,
            self.scripted,
            session,
            path,
            env,
            ["--mode", "rpc"],
        )
        self.process = subprocess.Popen(args, cwd=self.project, env=environment, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                        stderr=subprocess.PIPE, text=True, bufsize=1)  # fmt: skip
        threading.Thread(target=self._read, daemon=True).start()
        threading.Thread(
            target=lambda: self.stderr.extend(self.process.stderr), daemon=True
        ).start()
        self._ids = 0

    def _read(self):
        for line in self.process.stdout:
            if line.startswith("{"):
                self.lines.put(json.loads(line))
        self.lines.put(None)

    def send(self, record):
        self.process.stdin.write(json.dumps(record) + "\n")
        self.process.stdin.flush()

    def _handle(self, record):
        self.records.append(record)
        if record.get("type") != "extension_ui_request":
            return
        method = record["method"]
        if method == "notify":
            self.notifications.append(record["message"])
        elif method == "setStatus":
            self.statuses[record["statusKey"]] = record.get("statusText")
        elif method in ("select", "confirm", "input", "editor"):
            self.dialogs.append(record)
            answer = self.answer(record)
            reply = {"type": "extension_ui_response", "id": record["id"]}
            if answer is None:
                reply["cancelled"] = True
            elif method == "confirm":
                reply["confirmed"] = bool(answer)
            else:
                reply["value"] = answer
            self.send(reply)

    def wait(self, predicate, timeout=60, what="the condition"):
        """Handle records until `predicate(record)` holds for one, and return it."""
        end = time.time() + timeout
        while time.time() < end:
            try:
                record = self.lines.get(timeout=0.2)
            except queue.Empty:
                continue
            assert record is not None, (
                f"Pi exited while waiting for {what}: {''.join(self.stderr)[-2000:]}"
            )
            self._handle(record)
            if predicate(record):
                return record
        raise AssertionError(
            f"timed out after {timeout}s waiting for {what}; notifications {self.notifications}; stderr {''.join(self.stderr)[-2000:]}"
        )

    def command(self, **fields):
        """Send an RPC command and return its response data."""
        self._ids += 1
        ident = f"c{self._ids}"
        self.send({"id": ident, **fields})
        response = self.wait(
            lambda r: r.get("type") == "response" and r.get("id") == ident,
            what=f"the response to {fields.get('type')}",
        )
        assert response.get("success"), response
        return response.get("data")

    def prompt(self, text, steps=(), timeout=120):
        """Send a prompt and wait for the run it starts to settle; a slash command that starts no run returns at once."""
        self.scripted.steps = list(steps)
        before = len(self.scripted.requests)
        data = self.command(type="prompt", message=text)
        if (data or {}).get("disposition") == "handled":
            return data
        self.wait(
            lambda r: r.get("type") == "agent_end",
            timeout=timeout,
            what="the run to end",
        )
        assert len(self.scripted.requests) > before
        return data

    def wait_notification(self, text, timeout=60):
        """Handle records until a notification containing `text` has arrived (it may already have)."""
        end = time.time() + timeout
        while time.time() < end:
            if any(text in message for message in self.notifications):
                return next(
                    message for message in self.notifications if text in message
                )
            try:
                record = self.lines.get(timeout=0.2)
            except queue.Empty:
                continue
            assert record is not None, (
                f"Pi exited while waiting for {text!r}: {''.join(self.stderr)[-2000:]}"
            )
            self._handle(record)
        raise AssertionError(
            f"no notification containing {text!r}; got {self.notifications}"
        )

    def wait_dialog(self, after, timeout=60):
        """Handle records until more than `after` dialogs have been asked, and return the latest."""
        end = time.time() + timeout
        while len(self.dialogs) <= after:
            assert time.time() < end, f"no dialog was asked (have {len(self.dialogs)}); notifications {self.notifications}"
            try:
                record = self.lines.get(timeout=0.2)
            except queue.Empty:
                continue
            assert record is not None, f"Pi exited while waiting for a dialog: {''.join(self.stderr)[-2000:]}"
            self._handle(record)
        return self.dialogs[-1]

    def pump(self, seconds):
        """Handle records for `seconds`: time for an extension to act on a dialog answer."""
        end = time.time() + seconds
        while time.time() < end:
            try:
                record = self.lines.get(timeout=0.1)
            except queue.Empty:
                continue
            assert record is not None, f"Pi exited: {''.join(self.stderr)[-2000:]}"
            self._handle(record)

    def close(self):
        try:
            self.process.stdin.close()
            self.process.wait(timeout=20)
        except Exception:
            self.process.kill()
        self.scripted.stop()
