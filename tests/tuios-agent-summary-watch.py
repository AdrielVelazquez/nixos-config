import json
import os
from pathlib import Path
import select
import signal
import subprocess
import sys
import tempfile
import time
import unittest


script_path = Path(sys.argv.pop(1)).resolve()
filter_path = Path(sys.argv.pop(1)).resolve()

FAKE_TUIOS = '''
import json, os, pathlib, sys
root = pathlib.Path(os.environ["TUIOS_TEST_ROOT"])
if sys.argv[1:] == ["list-agents", "--all-sessions", "--json"]:
    if (root / "snapshot-fails").exists():
        sys.exit(9)
    print((root / "agents.json").read_text())
elif sys.argv[1:2] == ["subscribe"]:
    if os.environ.get("TUIOS_TEST_SUBSCRIBE_FAIL"):
        sys.exit(7)
    assert sys.argv[2] == "--types" and len(sys.argv) == 4, sys.argv
    types = set(sys.argv[3].split(","))
    # The real subscribe ACK is sent only after the subscription is active.
    print(json.dumps({"success": True, "seq": 1, "boot_id": "test"}), flush=True)
    with (root / "events").open() as events:
        for line in events:
            event = json.loads(line)
            if event["type"] in types or event["type"] == "gap":
                print(line, end="", flush=True)
else:
    raise AssertionError(sys.argv)
'''


class WatchTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        fake = self.root / "tuios"
        fake.write_text(f"#!{sys.executable}\n" + FAKE_TUIOS)
        fake.chmod(0o755)
        os.mkfifo(self.root / "events")
        self.events = os.open(self.root / "events", os.O_RDWR | os.O_NONBLOCK)
        self.addCleanup(os.close, self.events)
        self.env = {
            **os.environ,
            "PATH": str(self.root) + os.pathsep + os.environ["PATH"],
            "TUIOS_TEST_ROOT": str(self.root),
            "TUIOS_AGENT_SUMMARY_FILTER": str(filter_path),
        }
        self.buffer = b""
        self.set_agents("needs_input")

    def set_agents(self, *states):
        path = self.root / "next.json"
        path.write_text(json.dumps({"agents": [{"state": s} for s in states]}))
        path.replace(self.root / "agents.json")

    def start(self):
        self.process = subprocess.Popen(
            ["bash", str(script_path), "--watch"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=self.env,
            start_new_session=True,
            bufsize=0,
        )
        self.addCleanup(self.stop)

    def stop(self):
        try:
            os.killpg(self.process.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        self.process.communicate(timeout=5)

    def line(self):
        deadline = time.monotonic() + 3
        while b"\n" not in self.buffer:
            remaining = deadline - time.monotonic()
            self.assertGreater(remaining, 0, "no status update arrived")
            ready, _, _ = select.select([self.process.stdout], [], [], remaining)
            self.assertTrue(ready, "no status update arrived")
            chunk = os.read(self.process.stdout.fileno(), 4096)
            self.assertTrue(chunk, "watcher exited instead of waiting for the next raw event")
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        return line.decode()

    def event(self, kind="agent-state"):
        os.write(self.events, json.dumps({"type": kind, "session": "another-session"}).encode() + b"\n")

    def test_initial_snapshot_and_every_raw_transition_across_sessions(self):
        self.start()
        self.assertIn(" ! 1 needs you ", self.line())
        for state, text in [("working", " ◐ 1 working "), ("idle", " ○ 1 idle "), ("done", " ✓ 1 done ")]:
            self.set_agents(state)
            self.event()
            self.assertIn(text, self.line())

    def test_lifecycle_events_clear_empty_counts_and_recover(self):
        self.start()
        self.assertIn("needs you", self.line())
        for kind in ["window-created", "window-closed", "session-created", "session-closed"]:
            self.set_agents()
            self.event(kind)
            self.assertEqual(self.line(), "")
            self.set_agents("working")
            self.event()
            self.assertIn("working", self.line())

    def test_empty_start_and_gap_resynchronize_from_snapshot(self):
        self.set_agents()
        self.start()
        self.assertEqual(self.line(), "")
        self.set_agents("working", "working")
        self.event("gap")
        self.assertIn(" ◐ 2 working ", self.line())

    def test_snapshot_failure_clears_stale_text_without_losing_subscription(self):
        self.start()
        self.assertIn("needs you", self.line())
        failure = self.root / "snapshot-fails"
        failure.touch()
        self.event()
        self.assertEqual(self.line(), "")
        failure.unlink()
        self.set_agents("idle")
        self.event()
        self.assertIn("idle", self.line())

    def test_subscribe_failure_propagates(self):
        self.env["TUIOS_TEST_SUBSCRIBE_FAIL"] = "1"
        self.start()
        stdout, stderr = self.process.communicate(timeout=5)
        self.assertNotEqual(self.process.returncode, 0, stderr)
        self.assertEqual(stdout, b"")

    def test_one_shot_preserves_success_and_empty_exit_contract(self):
        result = subprocess.run(["bash", str(script_path)], env=self.env, capture_output=True, text=True, timeout=5)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("needs you", result.stdout)
        self.set_agents()
        result = subprocess.run(["bash", str(script_path)], env=self.env, capture_output=True, text=True, timeout=5)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(result.stdout, "")


unittest.main()
