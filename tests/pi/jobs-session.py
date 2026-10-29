"""Real Pi and the packaged upstream background extension; only the loopback model is scripted.

jobs-session.py PI EXTENSION OUTPUT
"""

import json
import os
import sys
import time
from contextlib import contextmanager
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from scripted_pi import Rpc, call  # noqa: E402

pi, extension, output = sys.argv[1:]
probe = str(Path(__file__).parent / "fixtures/background-probe.ts")


@contextmanager
def session(name):
    rpc = Rpc(pi, name, [extension, probe], {})
    try:
        yield rpc
    finally:
        rpc.close()
        out = Path(output)
        out.mkdir(parents=True, exist_ok=True)
        (out / f"{name}-events.json").write_text(json.dumps(rpc.records, indent=2))
        (out / f"{name}-requests.json").write_text(
            json.dumps(rpc.scripted.requests, indent=2)
        )
        assert rpc.process.returncode == 0, (rpc.process.returncode, rpc.stderr)
        assert not rpc.stderr, rpc.stderr


def wake(record):
    message = record.get("message", {})
    return (
        record.get("type") == "message_end"
        and message.get("role") == "custom"
        and message.get("customType") == "background-job"
    )


def wait_for_wake(rpc):
    rpc.wait(wake, timeout=15, what="a background completion message")


def wait_for_response(rpc, before):
    rpc.wait(
        lambda r: r.get("type") == "agent_end",
        timeout=15,
        what="the automatically resumed response",
    )
    assert len(rpc.scripted.requests) == before + 1, (
        "completion must cause exactly one new provider request"
    )


def contains(rpc, text):
    return text in json.dumps(rpc.scripted.requests[-1]["messages"])


def gated(marker, result):
    return f"while [ ! -e {marker} ]; do sleep 0.05; done; {result}"


def alive(pid):
    try:
        os.kill(pid, 0)
        stat = Path(f"/proc/{pid}/stat")
        return not stat.exists() or stat.read_text().split(") ", 1)[1].split()[0] != "Z"
    except (ProcessLookupError, FileNotFoundError):
        return False


def gone(pids):
    deadline = time.monotonic() + 8
    while any(alive(pid) for pid in pids) and time.monotonic() < deadline:
        time.sleep(0.05)
    assert not any(alive(pid) for pid in pids), f"live worker left behind: {pids}"


def worker_pids(project):
    markers = [project / "parent.pid", project / "child.pid"]
    deadline = time.monotonic() + 5
    while (
        not all(marker.exists() and marker.read_text().strip() for marker in markers)
        and time.monotonic() < deadline
    ):
        time.sleep(0.05)
    return [int(marker.read_text()) for marker in markers]


def worker_command(project):
    return f"echo $$ > {project}/parent.pid; sleep 60 & echo $! > {project}/child.pid; wait"


def completion_and_responsiveness():
    with session("background-wake") as rpc:
        rpc.prompt("Inspect the available tools.", [lambda *_: call("jobs_fixture")])
        tools = set(json.loads(rpc.scripted.results[0]))
        assert {"bg_run", "bg_status", "bg_kill"} <= tools, (
            f"missing replacement tools: {tools}"
        )
        assert "job" not in tools, "two background managers are enabled"
        release = rpc.project / "release"
        rpc.prompt(
            "Start a background fixture.",
            [lambda *_: call("bg_run", command=gated(release, "echo WAKE_SENTINEL"))],
        )
        assert "Started bg1" in rpc.scripted.results[0], rpc.scripted.results
        rpc.scripted.steps = []
        rpc.prompt("Steering: acknowledge this while the job still runs.")
        assert not any(wake(record) for record in rpc.records), (
            "the job should still be waiting"
        )
        before = len(rpc.scripted.requests)
        release.touch()
        wait_for_wake(rpc)
        wait_for_response(rpc, before)
        assert contains(rpc, "WAKE_SENTINEL")
        rpc.pump(0.3)
        assert len(rpc.scripted.requests) == before + 1, "duplicate completion wake"
        rpc.prompt(
            "Inspect the finished job.", [lambda *_: call("bg_status", id="bg1")]
        )
        assert (
            "exit 0" in rpc.scripted.results[0]
            and "WAKE_SENTINEL" in rpc.scripted.results[0]
        )
    print(
        "PASS registration, idle auto-wake, foreground responsiveness and completed output",
        flush=True,
    )


def grouped_completions():
    with session("background-group") as rpc:
        first, second = rpc.project / "first", rpc.project / "second"
        commands = [gated(first, "echo PAIR_FIRST"), gated(second, "echo PAIR_SECOND")]
        rpc.prompt(
            "Start two fixtures in one turn.",
            [lambda *_: call("jobs_fixture", commands=commands)],
        )
        assert (
            "Started bg1" in rpc.scripted.results[0]
            and "Started bg2" in rpc.scripted.results[0]
        )
        rpc.scripted.steps = []
        before = len(rpc.scripted.requests)
        first.touch()
        wait_for_wake(rpc)
        rpc.pump(0.2)
        assert len(rpc.scripted.requests) == before, (
            "a successful sibling must not cause an early wake"
        )
        second.touch()
        wait_for_wake(rpc)
        wait_for_response(rpc, before)
        assert contains(rpc, "PAIR_FIRST") and contains(rpc, "PAIR_SECOND")
    print("PASS same-turn successful jobs produce one resumed response", flush=True)


def failure_does_not_wait_for_sibling():
    with session("background-failure") as rpc:
        first, second = rpc.project / "failure", rpc.project / "slow"
        commands = [
            gated(first, "echo FAILURE_SENTINEL; exit 7"),
            gated(second, "echo SLOW_SENTINEL"),
        ]
        rpc.prompt(
            "Start a failing fixture and a slow sibling.",
            [lambda *_: call("jobs_fixture", commands=commands)],
        )
        rpc.scripted.steps = []
        before = len(rpc.scripted.requests)
        first.touch()
        wait_for_wake(rpc)
        wait_for_response(rpc, before)
        assert contains(rpc, "exit 7") and contains(rpc, "FAILURE_SENTINEL")
        assert not second.exists(), (
            "the failure must be delivered while its sibling is still waiting"
        )
    print("PASS failure wakes without waiting for a successful sibling", flush=True)


def cancellation():
    with session("background-cancel") as rpc:
        rpc.prompt(
            "Start a cancellable worker.",
            [lambda *_: call("bg_run", command=worker_command(rpc.project))],
        )
        pids = worker_pids(rpc.project)
        rpc.prompt("Cancel the worker.", [lambda *_: call("bg_kill", id="bg1")])
        rpc.scripted.steps = []
        before = len(rpc.scripted.requests)
        gone(pids)
        rpc.pump(0.5)
        assert len(rpc.scripted.requests) == before, (
            "explicit cancellation must not start another model request"
        )
    print("PASS cancellation stops parent and child without an extra wake", flush=True)


def shutdown_cleanup():
    with session("background-shutdown") as rpc:
        rpc.prompt(
            "Start a worker that must not outlive Pi.",
            [lambda *_: call("bg_run", command=worker_command(rpc.project))],
        )
        pids = worker_pids(rpc.project)
        rpc.scripted.steps = []
    gone(pids)
    print(
        "PASS shutdown stops parent and child without stale-context errors", flush=True
    )


def unexpected_slow_bash():
    with session("background-handoff") as rpc:
        release, executions = rpc.project / "release", rpc.project / "executions"
        command = f"echo started >> {executions}; " + gated(
            release, "echo HANDOFF_SENTINEL"
        )
        rpc.prompt(
            "Run a slow fixture with a short timeout.",
            [lambda *_: call("bash", command=command, timeout=0.25)],
        )
        assert "bg1" in rpc.scripted.results[0], rpc.scripted.results
        rpc.scripted.steps = []
        before = len(rpc.scripted.requests)
        release.touch()
        wait_for_wake(rpc)
        wait_for_response(rpc, before)
        assert contains(rpc, "HANDOFF_SENTINEL")
        assert executions.read_text().splitlines() == ["started"], (
            "handoff must not run the command twice"
        )
    print("PASS Bash timeout hands off once and completion resumes Pi", flush=True)


for case in [
    completion_and_responsiveness,
    grouped_completions,
    failure_does_not_wait_for_sibling,
    cancellation,
    shutdown_cleanup,
    unexpected_slow_bash,
]:
    case()
print("PASS packaged pi-background integration", flush=True)
