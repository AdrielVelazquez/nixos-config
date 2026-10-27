#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
import threading

ROOT = Path(__file__).resolve().parents[1]
HELPER = ROOT / "packages/headroom-pi.py"
FAKE = ROOT / "tests/pi/fake-headroom.py"


def wait_for(predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.025)
    raise AssertionError("timed out waiting for fixture state")


def healthy(url):
    try:
        with urllib.request.urlopen(url + "/health", timeout=0.3) as response:
            return response.status == 200
    except Exception:
        return False


class Launcher(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(
            prefix="headroom-pi-test-", dir=os.environ.get("TMPDIR", "/tmp/opencode")
        )
        self.root = Path(self.temp.name)
        for name in ["home", "runtime", "project"]:
            (self.root / name).mkdir(mode=0o700)
        self.env = {
            "PATH": os.environ["PATH"],
            "HOME": str(self.root / "home"),
            "XDG_RUNTIME_DIR": str(self.root / "runtime"),
        }
        self.config = {
            "version": 1,
            "piCommand": [sys.executable, "-E", str(FAKE), "pi"],
            "proxyCommand": [sys.executable, "-E", str(FAKE)],
            "port": 0,
            "startupTimeout": 3,
            "memory": True,
            "codeGraph": False,
            "tuningEnv": {"HEADROOM_MODE": "cache"},
            "upstreamOrigins": ["https://upstream.example"],
            "adapters": [
                {
                    "urlEnv": "LLM_PLATFORM_INFERENCE_PROXY_URL",
                    "requiredEnv": "LLM_PLATFORM_INFERENCE_PROXY_REQUIRED",
                }
            ],
        }
        self.manifest = self.root / "config.json"
        self.processes = []

    def tearDown(self):
        for process in self.processes:
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()
        # Proxies are session-owned; tests leave no real user state.
        time.sleep(0.3)
        self.temp.cleanup()

    def start(
        self, name="one", hold=False, code=0, extra_env=None, extra_args=None, cwd=None
    ):
        self.manifest.write_text(json.dumps(self.config))
        capture, until = self.root / (name + ".json"), self.root / (name + ".stop")
        args = [
            sys.executable,
            "-E",
            str(HELPER),
            "--config",
            str(self.manifest),
            "--",
            "--capture",
            str(capture),
            "--exit",
            str(code),
        ]
        if hold:
            args += ["--until", str(until)]
        args += extra_args or []
        process = subprocess.Popen(
            args,
            cwd=cwd or self.root / "project",
            env={**self.env, **(extra_env or {})},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.processes.append(process)
        return process, capture, until

    def capture(self, process, path):
        wait_for(lambda: path.exists() or process.poll() is not None)
        if not path.exists():
            self.fail(process.communicate()[1])
        return json.loads(path.read_text())

    def test_routes_required_proxy_and_preserves_child_exit_code(self):
        process, path, _ = self.start(
            code=7,
            extra_env={
                "PYTHONPATH": "/SYNTHETIC_LEAK",
                "PYTHONHOME": "/SYNTHETIC_LEAK",
            },
        )
        captured = self.capture(process, path)
        self.assertEqual(captured["LLM_PLATFORM_INFERENCE_PROXY_REQUIRED"], "1")
        self.assertEqual(
            captured["LLM_PLATFORM_INFERENCE_PROXY_URL"], captured["HEADROOM_PROXY_URL"]
        )
        self.assertIsNone(captured["PYTHONPATH"])
        self.assertIsNone(captured["PYTHONHOME"])
        self.assertEqual(process.wait(timeout=8), 7)
        wait_for(lambda: not healthy(captured["HEADROOM_PROXY_URL"]))

    def test_concurrent_sessions_share_only_the_owned_compatible_proxy(self):
        a, ap, astop = self.start("a", hold=True)
        first = self.capture(a, ap)
        b, bp, bstop = self.start("b", hold=True)
        second = self.capture(b, bp)
        self.assertEqual(first["HEADROOM_PROXY_URL"], second["HEADROOM_PROXY_URL"])
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        self.assertTrue(healthy(second["HEADROOM_PROXY_URL"]))
        bstop.touch()
        self.assertEqual(b.wait(timeout=8), 0)
        wait_for(lambda: not healthy(second["HEADROOM_PROXY_URL"]))

    def test_startup_failure_never_launches_unproxied_pi(self):
        self.config["proxyCommand"] = [
            sys.executable,
            "-E",
            "-c",
            "raise SystemExit(1)",
        ]
        process, path, _ = self.start()
        self.assertNotEqual(process.wait(timeout=8), 0)
        self.assertFalse(path.exists())

    def test_existing_project_memory_database_is_not_replaced(self):
        folder = self.root / "project/.headroom"
        folder.mkdir()
        database = folder / "memory.db"
        database.write_bytes(b"SYNTHETIC_EXISTING_DATABASE")
        process, path, _ = self.start()
        captured = self.capture(process, path)
        self.assertEqual(captured["HEADROOM_PI_MEMORY_DB"], str(database))
        self.assertEqual(process.wait(timeout=8), 0)
        self.assertEqual(database.read_bytes(), b"SYNTHETIC_EXISTING_DATABASE")

    def test_new_memory_database_has_a_private_parent_before_client_start(self):
        process, path, _ = self.start()
        captured = self.capture(process, path)
        parent = Path(captured["HEADROOM_PI_MEMORY_DB"]).parent
        self.assertTrue(parent.is_dir())
        self.assertEqual(parent.stat().st_mode & 0o777, 0o700)
        self.assertEqual(process.wait(timeout=8), 0)

    def test_an_occupied_foreign_port_is_never_reused_or_terminated(self):
        class Handler(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"foreign")

            def log_message(self, *args):
                pass

        server = HTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        try:
            self.config["port"] = server.server_address[1]
            process, path, _ = self.start()
            self.assertNotEqual(process.wait(timeout=8), 0)
            self.assertFalse(path.exists())
            self.assertTrue(healthy(f"http://127.0.0.1:{server.server_address[1]}"))
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_different_startup_tuning_gets_a_separate_proxy_without_stopping_the_old_one(
        self,
    ):
        a, ap, astop = self.start("cache", hold=True)
        first = self.capture(a, ap)
        self.config["tuningEnv"]["HEADROOM_MODE"] = "token"
        b, bp, bstop = self.start("token", hold=True)
        second = self.capture(b, bp)
        self.assertNotEqual(first["HEADROOM_PROXY_URL"], second["HEADROOM_PROXY_URL"])
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        self.assertTrue(healthy(second["HEADROOM_PROXY_URL"]))
        bstop.touch()
        self.assertEqual(b.wait(timeout=8), 0)

    def test_signal_is_forwarded_and_proxy_is_cleaned_up(self):
        process, path, _ = self.start(hold=True)
        captured = self.capture(process, path)
        process.terminate()
        self.assertEqual(process.wait(timeout=8), 143)
        wait_for(lambda: not healthy(captured["HEADROOM_PROXY_URL"]))

    def test_admitted_background_run_reservation_outlives_the_parent_launcher(self):
        process, path, _ = self.start(extra_args=["--spawn-worker"])
        captured = self.capture(process, path)
        self.assertEqual(process.wait(timeout=8), 0)
        self.assertTrue(
            healthy(captured["HEADROOM_PROXY_URL"]),
            "parent exit killed an admitted pending child",
        )
        wait_for(lambda: not healthy(captured["HEADROOM_PROXY_URL"]))

    def test_proxy_bootstrap_does_not_inherit_foreign_python_paths(self):
        self.config["proxyCommand"].append("verify-proxy-env")
        process, path, _ = self.start(
            extra_env={"PYTHONHOME": "/SYNTHETIC_LEAK", "PYTHONPATH": "/SYNTHETIC_LEAK"}
        )
        self.capture(process, path)
        self.assertEqual(process.wait(timeout=8), 0)

    def test_memory_proxy_cannot_inject_mutable_tools_around_native_child_allowlists(
        self,
    ):
        self.config["proxyCommand"].append("verify-memory-policy")
        process, path, _ = self.start()
        self.capture(process, path)
        self.assertEqual(process.wait(timeout=8), 0)

    def test_code_graph_skips_only_home_and_filesystem_root(self):
        home = self.root / "home"
        nested = home / "nested"
        nested.mkdir()
        alias = self.root / "home-alias"
        alias.symlink_to(home, target_is_directory=True)
        self.config["codeGraph"] = True
        for name, cwd, home_env, memory, graph in [
            ("home", home, home, True, False),
            ("home-alias", home, alias, True, False),
            ("root", Path("/"), home, False, False),
            ("project", self.root / "project", home, True, True),
            ("home-child", nested, home, True, True),
        ]:
            with self.subTest(directory=name):
                self.config["memory"] = memory
                arguments = self.root / (name + "-proxy-args.json")
                process, path, stop = self.start(
                    name,
                    hold=True,
                    cwd=cwd,
                    extra_env={
                        "HOME": str(home_env),
                        "FIXTURE_PROXY_ARGS": str(arguments),
                    },
                )
                captured = self.capture(process, path)
                try:
                    self.assertEqual(
                        "--code-graph" in json.loads(arguments.read_text()), graph
                    )
                    self.assertEqual(
                        captured["LLM_PLATFORM_INFERENCE_PROXY_REQUIRED"], "1"
                    )
                    self.assertEqual(
                        captured["LLM_PLATFORM_INFERENCE_PROXY_URL"],
                        captured["HEADROOM_PROXY_URL"],
                    )
                    self.assertTrue(healthy(captured["HEADROOM_PROXY_URL"]))
                    if memory:
                        self.assertTrue(
                            Path(captured["HEADROOM_PI_MEMORY_DB"]).parent.is_dir()
                        )
                finally:
                    stop.touch()
                    self.assertEqual(process.wait(timeout=8), 0)
                    wait_for(
                        lambda url=captured["HEADROOM_PROXY_URL"]: not healthy(url)
                    )

    def test_graph_proxy_is_rooted_at_the_repository_not_a_nested_launch_directory(
        self,
    ):
        project = self.root / "project"
        subprocess.run(["git", "init", "-q", "-b", "main", str(project)], check=True)
        nested = project / "nested"
        nested.mkdir()
        # start() normally launches in project; use a one-shot piCommand to
        # re-enter the launcher from the nested directory through its cwd.
        self.config["codeGraph"] = True
        capture = self.root / "proxy-cwd"
        self.manifest.write_text(json.dumps(self.config))
        process = subprocess.Popen(
            [
                sys.executable,
                "-E",
                str(HELPER),
                "--config",
                str(self.manifest),
                "--",
                "--capture",
                str(self.root / "child.json"),
            ],
            cwd=nested,
            env={**self.env, "FIXTURE_PROXY_CWD": str(capture)},
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        self.processes.append(process)
        self.capture(process, self.root / "child.json")
        self.assertEqual(capture.read_text(), str(project))
        self.assertEqual(process.wait(timeout=8), 0)

    def test_a_git_worktree_uses_its_own_graph_root_and_existing_memory_database(self):
        repository = self.root / "project"
        subprocess.run(["git", "init", "-q", "-b", "main", str(repository)], check=True)
        subprocess.run(
            [
                "git",
                "-C",
                str(repository),
                "-c",
                "user.name=fixture",
                "-c",
                "user.email=fixture@example.invalid",
                "commit",
                "-q",
                "--allow-empty",
                "-m",
                "fixture",
            ],
            check=True,
        )
        worktree = self.root / "worktree"
        subprocess.run(
            [
                "git",
                "-C",
                str(repository),
                "worktree",
                "add",
                "-q",
                "--detach",
                str(worktree),
                "HEAD",
            ],
            check=True,
        )
        (worktree / "nested").mkdir()
        (worktree / ".headroom").mkdir()
        database = worktree / ".headroom/memory.db"
        database.write_bytes(b"SYNTHETIC_WORKTREE_MEMORY")
        capture = self.root / "worktree-proxy-cwd"
        process, path, _ = self.start(
            cwd=worktree / "nested", extra_env={"FIXTURE_PROXY_CWD": str(capture)}
        )
        data = self.capture(process, path)
        self.assertEqual(capture.read_text(), str(worktree))
        self.assertEqual(data["HEADROOM_PI_MEMORY_DB"], str(database))
        self.assertEqual(process.wait(timeout=8), 0)


if __name__ == "__main__":
    unittest.main()
