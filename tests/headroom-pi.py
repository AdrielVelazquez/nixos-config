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
            "graphCommand": [sys.executable, "-E", str(FAKE), "graph"],
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

    def test_all_provider_routes_off_retains_managed_session_without_inference_contract(
        self,
    ):
        self.config["adapters"] = []
        self.config["upstreamOrigins"] = []
        process, path, _ = self.start()
        captured = self.capture(process, path)
        self.assertIsNone(captured["LLM_PLATFORM_INFERENCE_PROXY_URL"])
        self.assertIsNone(captured["LLM_PLATFORM_INFERENCE_PROXY_REQUIRED"])
        self.assertTrue(captured["HEADROOM_PROXY_URL"].startswith("http://127.0.0.1:"))
        self.assertEqual(process.wait(timeout=8), 0)
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

    def test_different_projects_share_one_proxy_and_keep_independent_resources(self):
        other = self.root / "other"
        other.mkdir()
        a, ap, astop = self.start("a", hold=True)
        b, bp, bstop = self.start("b", hold=True, cwd=other)
        first = self.capture(a, ap)
        second = self.capture(b, bp)
        self.assertEqual(first["HEADROOM_PROXY_URL"], second["HEADROOM_PROXY_URL"])
        self.assertNotEqual(
            first["HEADROOM_PI_STATE_DIR"], second["HEADROOM_PI_STATE_DIR"]
        )
        self.assertNotEqual(
            first["HEADROOM_PI_MEMORY_DB"], second["HEADROOM_PI_MEMORY_DB"]
        )
        states = [
            json.loads((Path(item["HEADROOM_PI_STATE_DIR"]) / "state.json").read_text())
            for item in [first, second]
        ]
        self.assertEqual(states[0]["proxyPid"], states[1]["proxyPid"])
        self.assertNotIn(
            Path(f"/proc/{states[0]['proxyPid']}/cwd").resolve(),
            [self.root / "project", other],
        )
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        wait_for(
            lambda: (
                not json.loads(
                    (Path(first["HEADROOM_PI_STATE_DIR"]) / "state.json").read_text()
                )["ready"]
            )
        )
        self.assertTrue(healthy(second["HEADROOM_PROXY_URL"]))
        bstop.touch()
        self.assertEqual(b.wait(timeout=8), 0)
        wait_for(lambda: not healthy(second["HEADROOM_PROXY_URL"]))

    def test_nested_directories_reuse_the_same_project_resources(self):
        project = self.root / "project"
        subprocess.run(["git", "init", "-q", "-b", "main", str(project)], check=True)
        nested = project / "nested"
        nested.mkdir()
        a, ap, astop = self.start("root", hold=True)
        first = self.capture(a, ap)
        b, bp, bstop = self.start("nested", hold=True, cwd=nested)
        second = self.capture(b, bp)
        self.assertEqual(first["HEADROOM_PROXY_URL"], second["HEADROOM_PROXY_URL"])
        self.assertEqual(
            first["HEADROOM_PI_STATE_DIR"], second["HEADROOM_PI_STATE_DIR"]
        )
        self.assertEqual(
            first["HEADROOM_PI_MEMORY_DB"], second["HEADROOM_PI_MEMORY_DB"]
        )
        astop.touch()
        bstop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        self.assertEqual(b.wait(timeout=8), 0)

    def test_owned_proxy_is_recovered_after_its_shared_manager_dies(self):
        a, ap, astop = self.start("a", hold=True)
        first = self.capture(a, ap)
        shared = Path(first["HEADROOM_PI_STATE_DIR"]).parent / "shared-proxy"
        before = json.loads((shared / "state.json").read_text())
        os.kill(before["managerPid"], 9)
        other = self.root / "other"
        other.mkdir()
        b, bp, bstop = self.start("b", hold=True, cwd=other)
        second = self.capture(b, bp)
        after = json.loads((shared / "state.json").read_text())
        self.assertEqual(first["HEADROOM_PROXY_URL"], second["HEADROOM_PROXY_URL"])
        self.assertEqual(before["proxyPid"], after["proxyPid"])
        self.assertNotEqual(before["managerPid"], after["managerPid"])
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        self.assertTrue(healthy(second["HEADROOM_PROXY_URL"]))
        bstop.touch()
        self.assertEqual(b.wait(timeout=8), 0)
        wait_for(lambda: not healthy(second["HEADROOM_PROXY_URL"]))

    def test_project_options_do_not_split_inference_policy(self):
        a, ap, astop = self.start("memory", hold=True)
        first = self.capture(a, ap)
        other = self.root / "other"
        other.mkdir()
        self.config.update(memory=False, codeGraph=True)
        b, bp, bstop = self.start("graph", hold=True, cwd=other)
        second = self.capture(b, bp)
        self.assertEqual(first["HEADROOM_PROXY_URL"], second["HEADROOM_PROXY_URL"])
        self.assertFalse(Path(second["HEADROOM_PI_MEMORY_DB"]).parent.exists())
        state = json.loads(
            (Path(second["HEADROOM_PI_STATE_DIR"]) / "state.json").read_text()
        )
        self.assertTrue(state["graphPid"])
        astop.touch()
        bstop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        self.assertEqual(b.wait(timeout=8), 0)

    def test_graph_startup_failure_does_not_stop_another_projects_proxy(self):
        a, ap, astop = self.start("a", hold=True)
        first = self.capture(a, ap)
        other = self.root / "other"
        other.mkdir()
        self.config.update(codeGraph=True, graphCommand=["/nonexistent-graph-fixture"])
        b, bp, _ = self.start("b", cwd=other)
        self.assertNotEqual(b.wait(timeout=8), 0)
        self.assertFalse(bp.exists())
        self.assertTrue(healthy(first["HEADROOM_PROXY_URL"]))
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        wait_for(lambda: not healthy(first["HEADROOM_PROXY_URL"]))

    def test_changed_executable_origins_or_port_never_start_a_second_proxy(self):
        a, ap, astop = self.start("a", hold=True)
        first = self.capture(a, ap)
        original = dict(self.config)
        for name, update in [
            ("executable", {"proxyCommand": ["/nonexistent-proxy-fixture"]}),
            ("origins", {"upstreamOrigins": ["https://other.example"]}),
            ("port", {"port": 8787}),
        ]:
            with self.subTest(policy=name):
                self.config = {**original, **update}
                b, bp, _ = self.start(name)
                self.assertNotEqual(b.wait(timeout=8), 0)
                self.assertFalse(bp.exists())
                self.assertIn("incompatible", b.stderr.read().lower())
                self.assertTrue(healthy(first["HEADROOM_PROXY_URL"]))
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        wait_for(lambda: not healthy(first["HEADROOM_PROXY_URL"]))

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

    def test_unconfigured_environment_tuning_is_checked_without_persisting_credentials(
        self,
    ):
        credential = "SYNTHETIC_PRIVATE_PROXY_TOKEN"
        a, ap, astop = self.start(
            "a",
            hold=True,
            extra_env={
                "HEADROOM_TARGET_RATIO": "0.5",
                "HEADROOM_PROXY_TOKEN": credential,
            },
        )
        first = self.capture(a, ap)
        b, bp, _ = self.start(
            "b",
            extra_env={
                "HEADROOM_TARGET_RATIO": "0.9",
                "HEADROOM_PROXY_TOKEN": credential,
            },
        )
        self.assertNotEqual(b.wait(timeout=8), 0)
        self.assertFalse(bp.exists())
        self.assertIn("incompatible", b.stderr.read().lower())
        base = Path(first["HEADROOM_PI_STATE_DIR"]).parent
        for path in base.rglob("*.json"):
            self.assertNotIn(credential, path.read_text())
        self.assertTrue(healthy(first["HEADROOM_PROXY_URL"]))
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        wait_for(lambda: not healthy(first["HEADROOM_PROXY_URL"]))

    def test_incompatible_tuning_is_refused_without_stopping_the_shared_proxy(self):
        a, ap, astop = self.start("cache", hold=True)
        first = self.capture(a, ap)
        self.config["tuningEnv"]["HEADROOM_MODE"] = "token"
        b, bp, _ = self.start("token")
        self.assertNotEqual(b.wait(timeout=8), 0)
        self.assertFalse(bp.exists())
        self.assertIn("incompatible", b.stderr.read().lower())
        self.assertTrue(healthy(first["HEADROOM_PROXY_URL"]))
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        wait_for(lambda: not healthy(first["HEADROOM_PROXY_URL"]))

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
                    self.assertNotIn("--code-graph", json.loads(arguments.read_text()))
                    state = json.loads(
                        (
                            Path(captured["HEADROOM_PI_STATE_DIR"]) / "state.json"
                        ).read_text()
                    )
                    self.assertEqual(bool(state.get("graphPid")), graph)
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

    def test_graph_sidecar_is_rooted_at_the_repository_not_a_nested_directory(self):
        project = self.root / "project"
        subprocess.run(["git", "init", "-q", "-b", "main", str(project)], check=True)
        nested = project / "nested"
        nested.mkdir()
        self.config["codeGraph"] = True
        capture = self.root / "graph-cwd"
        process, path, _ = self.start(
            cwd=nested, extra_env={"FIXTURE_GRAPH_CWD": str(capture)}
        )
        self.capture(process, path)
        self.assertEqual(capture.read_text(), str(project))
        self.assertEqual(process.wait(timeout=8), 0)

    def test_project_graph_cleanup_does_not_stop_another_project_or_proxy(self):
        self.config["codeGraph"] = True
        other = self.root / "other"
        other.mkdir()
        a, ap, astop = self.start("a", hold=True)
        first = self.capture(a, ap)
        b, bp, bstop = self.start("b", hold=True, cwd=other)
        second = self.capture(b, bp)
        states = [
            json.loads((Path(item["HEADROOM_PI_STATE_DIR"]) / "state.json").read_text())
            for item in [first, second]
        ]
        self.assertNotEqual(states[0].get("graphPid"), states[1].get("graphPid"))
        for state, project in zip(states, [self.root / "project", other]):
            self.assertEqual(Path(f"/proc/{state['graphPid']}/cwd").resolve(), project)
        astop.touch()
        self.assertEqual(a.wait(timeout=8), 0)
        wait_for(lambda: not Path(f"/proc/{states[0]['graphPid']}").exists())
        self.assertTrue(Path(f"/proc/{states[1]['graphPid']}").exists())
        self.assertTrue(healthy(second["HEADROOM_PROXY_URL"]))
        bstop.touch()
        self.assertEqual(b.wait(timeout=8), 0)
        wait_for(lambda: not healthy(second["HEADROOM_PROXY_URL"]))

    def test_new_worktree_memory_does_not_dirty_the_checkout_or_disappear_with_it(self):
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
        process, path, _ = self.start(cwd=worktree)
        captured = self.capture(process, path)
        database = Path(captured["HEADROOM_PI_MEMORY_DB"])
        database.write_bytes(b"SYNTHETIC_PERSISTENT_WORKTREE_MEMORY")
        self.assertEqual(process.wait(timeout=8), 0)
        status = subprocess.check_output(
            ["git", "-C", str(worktree), "status", "--porcelain"], text=True
        )
        self.assertEqual(
            status,
            "",
            "private memory must not enter the native worktree patch handoff",
        )
        subprocess.run(
            ["git", "-C", str(repository), "worktree", "remove", str(worktree)],
            check=True,
        )
        self.assertEqual(database.read_bytes(), b"SYNTHETIC_PERSISTENT_WORKTREE_MEMORY")

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
        self.config["codeGraph"] = True
        capture = self.root / "worktree-graph-cwd"
        process, path, _ = self.start(
            cwd=worktree / "nested", extra_env={"FIXTURE_GRAPH_CWD": str(capture)}
        )
        data = self.capture(process, path)
        self.assertEqual(capture.read_text(), str(worktree))
        self.assertEqual(data["HEADROOM_PI_MEMORY_DB"], str(database))
        self.assertEqual(process.wait(timeout=8), 0)


if __name__ == "__main__":
    unittest.main()
