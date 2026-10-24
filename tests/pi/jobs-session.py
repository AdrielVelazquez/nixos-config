"""Real Pi with the background job tool: start, read with a wait, stop, and nothing left behind when Pi exits.

  jobs-session.py PI EXTENSION OUTPUT
"""

import os
import re
import sys
import tempfile
import time
from pathlib import Path

sys.path.insert(0, os.path.dirname(__file__))
from scripted_pi import call, run  # noqa: E402

pi, extension, output = sys.argv[1:]


def alive(pid):
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def lifecycle():
    scratch = Path(tempfile.mkdtemp(prefix="pi-jobs-"))
    marker = scratch / "worker.pid"
    command = f"echo $$ > {marker}; echo booting; sleep 1; echo ready; sleep 60"
    cursor = {}

    def read(results, _project):
        cursor["value"] = re.search(r"cursor: (\d+)", results[1]).group(1)
        return call("job", op="output", id=1, since=int(cursor["value"]), wait=20)

    steps = [
        lambda r, p: call("job", op="start", command=command, name="worker"),
        lambda r, p: call("job", op="output", id=1, wait=20),
        read,
        lambda r, p: call("job", op="list"),
        lambda r, p: call("job", op="stop", id=1),
        lambda r, p: call("bash", command="echo the session went on while it ran"),
    ]
    session = run(pi, "lifecycle", [extension], {}, steps, out=output)
    started, first, second, listed, stopped, after = session.results
    assert started.startswith("Started #1 worker · running"), started
    assert "booting" in first and "ready" not in first, first
    assert "ready" in second and "booting" not in second, "the cursor returns only what is new: " + second
    assert "#1 worker · running" in listed, listed
    assert "Stopped #1 worker · killed by SIGTERM" in stopped, stopped
    assert "the session went on" in after
    pid = int(marker.read_text())
    deadline = time.time() + 5
    while alive(pid) and time.time() < deadline:
        time.sleep(0.1)
    assert not alive(pid), "the stopped job's process is gone"
    print("PASS lifecycle: start, wait for output, read only what is new, list, stop", flush=True)


def survives_nothing():
    scratch = Path(tempfile.mkdtemp(prefix="pi-jobs-exit-"))
    marker = scratch / "orphan.pid"
    steps = [lambda r, p: call("job", op="start", command=f"echo $$ > {marker}; sleep 120", name="orphan")]
    run(pi, "exit", [extension], {}, steps, out=output)
    deadline = time.time() + 5
    while not marker.exists() and time.time() < deadline:
        time.sleep(0.1)
    pid = int(marker.read_text())
    deadline = time.time() + 10
    while alive(pid) and time.time() < deadline:
        time.sleep(0.1)
    assert not alive(pid), "a job left running when Pi exits must not outlive it"
    print("PASS cleanup: Pi exiting with a job running takes the job with it", flush=True)


lifecycle()
survives_nothing()
print("PASS: real Pi with background jobs", flush=True)
