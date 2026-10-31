#!/usr/bin/env python3
"""Exercise the graph sidecar lifecycle without indexing real user files."""

import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import time
import unittest

HELPER = Path(__file__).resolve().parents[1] / "packages/headroom-code-graph.py"


class GraphSidecar(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        package = self.root / "headroom/graph"
        package.mkdir(parents=True)
        (package.parent / "__init__.py").touch()
        (package / "__init__.py").touch()
        (package / "watcher.py").write_text(
            "import json, os\nfrom pathlib import Path\n"
            "class CodeGraphWatcher:\n"
            " def __init__(self, project_dir, cbm_binary):\n"
            "  self.project = str(project_dir); self.binary = cbm_binary\n"
            " def start(self):\n"
            "  Path('started.json').write_text(json.dumps([self.project, self.binary]))\n"
            "  return os.environ.get('FAIL_GRAPH') != '1'\n"
            " def stop(self):\n"
            "  Path('stopped').touch()\n"
        )
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=5)
        self.temp.cleanup()

    def start(self, fail=False):
        ready = self.root / "ready.json"
        process = subprocess.Popen(
            [
                sys.executable,
                str(HELPER),
                "--binary",
                "/fixture/codebase-memory-mcp",
                "--ready",
                str(ready),
            ],
            cwd=self.root,
            env={
                **os.environ,
                "PYTHONPATH": str(self.root),
                "FAIL_GRAPH": "1" if fail else "0",
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.processes.append(process)
        return process, ready

    def test_signals_stop_the_project_watcher_after_readiness(self):
        process, ready = self.start()
        deadline = time.monotonic() + 5
        while (
            not ready.exists()
            and process.poll() is None
            and time.monotonic() < deadline
        ):
            time.sleep(0.02)
        self.assertTrue(
            ready.exists(), "the sidecar must publish readiness after watcher startup"
        )
        self.assertEqual(
            json.loads((self.root / "started.json").read_text()),
            [str(self.root), "/fixture/codebase-memory-mcp"],
        )
        self.assertEqual(json.loads(ready.read_text())["project"], str(self.root))
        process.terminate()
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertTrue((self.root / "stopped").exists())
        self.assertFalse(ready.exists())

    def test_stale_temporary_marker_does_not_block_startup(self):
        stale = self.root / "ready.tmp"
        stale.write_text("previous interrupted startup")
        process, ready = self.start()
        deadline = time.monotonic() + 5
        while (
            not ready.exists()
            and process.poll() is None
            and time.monotonic() < deadline
        ):
            time.sleep(0.02)
        self.assertTrue(
            ready.exists(), "a prior temporary marker must not block the next owner"
        )
        process.terminate()
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertEqual(stale.read_text(), "previous interrupted startup")

    def test_failed_watcher_start_never_publishes_readiness(self):
        process, ready = self.start(fail=True)
        self.assertNotEqual(process.wait(timeout=5), 0)
        self.assertTrue((self.root / "stopped").exists())
        self.assertFalse(ready.exists())

    @unittest.skipUnless(
        os.environ.get("PI_TEST_GRAPH_LAUNCHER"), "requires the Nix graph closure"
    )
    def test_real_packaged_watcher_starts_and_stops_in_its_project(self):
        launcher = Path(os.environ["PI_TEST_GRAPH_LAUNCHER"]).read_text()
        command = next(
            shlex.split(line)
            for line in launcher.splitlines()
            if line.startswith("exec ")
        )
        config = json.loads(Path(command[command.index("--config") + 1]).read_text())
        self.assertEqual(config["port"], 8787)
        project = self.root / "project"
        project.mkdir()
        (project / "example.py").write_text("def example(): return 1\n")
        ready = self.root / "real-ready.json"
        process = subprocess.Popen(
            config["graphCommand"] + ["--ready", str(ready)],
            cwd=project,
            env={
                **os.environ,
                "HOME": str(self.root),
                "XDG_CACHE_HOME": str(self.root / "cache"),
            },
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )
        self.processes.append(process)
        deadline = time.monotonic() + 15
        while (
            not ready.exists()
            and process.poll() is None
            and time.monotonic() < deadline
        ):
            time.sleep(0.05)
        if not ready.exists():
            process.terminate()
            output = process.communicate(timeout=5)
            self.fail(f"real graph watcher failed to start: {output!r}")
        self.assertEqual(json.loads(ready.read_text())["project"], str(project))
        process.terminate()
        self.assertEqual(process.wait(timeout=5), 0)
        self.assertFalse(ready.exists())


if __name__ == "__main__":
    unittest.main()
