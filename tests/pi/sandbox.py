import contextlib
import fcntl
import importlib.util
import io
import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

SOURCE = Path(
    os.environ.get(
        "PI_SANDBOX_TEST_SOURCE",
        Path(__file__).resolve().parents[2] / "packages" / "pi-sandbox.py",
    )
)


class SandboxTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(
            SOURCE.is_file(), "the sandbox launcher has not been implemented"
        )
        spec = importlib.util.spec_from_file_location("pi_sandbox", SOURCE)
        self.module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.module)
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.home = self.root / "home"
        self.home.mkdir()
        self.repo = self.home / "projects" / "repo with spaces; touch OWNED"
        self.repo.mkdir(parents=True)
        self.git = shutil.which("git")
        subprocess.run([self.git, "init", "-q", str(self.repo)], check=True)
        self.log = self.root / "runtime.jsonl"
        self.runtime = self.root / "msb"
        self.make_runtime()
        self.config = {
            "runtime": str(self.runtime),
            "git": self.git,
            "image": str(self.root / "image.tar.gz"),
            "imageTag": "pi-sandbox:fixture",
            "stateDir": str(self.home / ".local" / "state" / "pi-sandbox"),
            "hostHome": str(self.home),
            "guestHome": "/home/adriel",
            "guestCommand": "/bin/pi-sandbox-guest",
            "runtimePath": str(Path(self.git).parent),
            "caBundle": "/etc/ssl/certs/ca-certificates.crt",
            "cpus": 2,
            "memory": "4G",
            "networkPolicy": "public",
            "allowedHosts": [],
            "ports": [],
            "secretBindings": {},
        }
        self.options = self.module.parse_options([])[0]
        self.options.project = str(self.repo)

    def make_runtime(self, run_exit=0, load_exit=0):
        self.runtime.write_text(
            f"#!{sys.executable}\n"
            "import json, os, pathlib, sys\n"
            "args = sys.argv[1:]\n"
            "record = {'args': args, 'env': dict(os.environ)}\n"
            "if '--conf' in args:\n"
            "    record['config'] = json.loads(pathlib.Path(args[args.index('--conf') + 1]).read_text())\n"
            f"with open({str(self.log)!r}, 'a') as stream:\n"
            "    stream.write(json.dumps(record) + '\\n')\n"
            "if args[:2] == ['image', 'inspect']: sys.exit(1)\n"
            f"if args[:1] == ['load']: sys.exit({load_exit})\n"
            f"if args[:1] == ['run']: sys.exit({run_exit})\n"
        )
        self.runtime.chmod(0o755)

    def records(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def launch(self, args=None):
        with (
            mock.patch.object(self.module, "check_kvm"),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            return self.module.launch(self.config, self.options, args or [])

    def test_arguments_after_separator_are_only_guest_pi_arguments(self):
        options, args = self.module.parse_options(
            ["--project", str(self.repo), "--", "--model", "fixture", "hello world"]
        )
        self.assertEqual(options.project, str(self.repo))
        self.assertEqual(args, ["--model", "fixture", "hello world"])

    def test_repo_paths_are_data_not_shell_commands(self):
        self.assertEqual(self.launch(["-p", "hello; touch OWNED"]), 0)
        run = next(row for row in self.records() if row["args"][0] == "run")
        self.assertEqual(
            run["config"]["mounts"][0],
            {"bind": str(self.repo), "target": "/workspace", "readonly": False},
        )
        self.assertEqual(
            run["args"][-3:], ["/bin/pi-sandbox-guest", "-p", "hello; touch OWNED"]
        )
        self.assertFalse((Path.cwd() / "OWNED").exists())

    def test_mounts_refuse_home_ancestors_sensitive_subtrees_and_state(self):
        ssh = self.home / ".ssh"
        ssh.mkdir()
        nested = ssh / "repo"
        nested.mkdir()
        state = Path(self.config["stateDir"])
        state.mkdir(parents=True)
        for path in [self.home, self.home.parent, ssh, nested, state, state.parent]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                self.module.validate_host_path(path, self.home, state)

    def test_symlink_to_sensitive_directory_is_refused(self):
        ssh = self.home / ".ssh"
        ssh.mkdir()
        link = self.repo / "borrowed"
        link.symlink_to(ssh, target_is_directory=True)
        with self.assertRaises(ValueError):
            self.module.validate_host_path(
                link, self.home, Path(self.config["stateDir"])
            )

    def test_external_git_metadata_is_refused(self):
        external = self.root / "external.git"
        (self.repo / ".git").rename(external)
        (self.repo / ".git").write_text(f"gitdir: {external}\n")
        with self.assertRaisesRegex(ValueError, "Git metadata"):
            self.module.project_mount(self.repo, self.config)

    def test_host_environment_is_not_inherited(self):
        poison = {
            "ANTHROPIC_API_KEY": "host-secret",
            "SSH_AUTH_SOCK": "/host/agent",
            "MSB_BACKEND": "cloud",
            "MSB_PROFILE": "production",
            "MSB_API_KEY": "cloud-secret",
            "HTTP_PROXY": "http://host-credential-proxy",
            "PI_CODING_AGENT_DIR": "/host/pi",
            "TUIOS_SESSION": "host-pane",
            "PYTHONPATH": "/host/python",
            "LD_PRELOAD": "/host/preload.so",
        }
        with mock.patch.dict(os.environ, poison):
            self.assertEqual(self.launch(), 0)
        for record in self.records():
            env = record["env"]
            self.assertEqual(env["MSB_BACKEND"], "local")
            self.assertNotEqual(env["HOME"], str(self.home))
            for key in poison.keys() - {"MSB_BACKEND"}:
                self.assertNotIn(key, env)

    def test_guest_failure_is_propagated_and_vm_is_removed(self):
        self.make_runtime(run_exit=23)
        self.assertEqual(self.launch(), 23)
        records = self.records()
        verbs = [row["args"][0] for row in records]
        self.assertEqual(verbs, ["image", "load", "run", "stop", "rm"])
        run = records[2]["args"]
        name = run[run.index("--name") + 1]
        self.assertIn(name, records[-1]["args"])

    def test_failed_image_import_never_runs_pi_or_a_vm(self):
        self.make_runtime(load_exit=17)
        self.assertEqual(self.launch(), 17)
        self.assertEqual([row["args"][0] for row in self.records()], ["image", "load"])

    def test_read_only_extra_repo_is_explicitly_mounted(self):
        other = self.home / "other"
        other.mkdir()
        subprocess.run([self.git, "init", "-q", str(other)], check=True)
        self.options.repo_ro = [str(other)]
        self.assertEqual(self.launch(), 0)
        run = next(row for row in self.records() if row["args"][0] == "run")
        self.assertEqual(run["config"]["mounts"][1]["bind"], str(other))
        self.assertTrue(run["config"]["mounts"][1]["readonly"])
        self.assertTrue(
            run["config"]["mounts"][1]["target"].startswith("/repos/other-")
        )

    def test_secret_values_are_not_written_to_config_or_logs(self):
        secret = self.root / "token"
        secret.write_text("private-test-token\n")
        self.config["secretBindings"] = {
            "GITHUB_TOKEN": {
                "sourceFile": str(secret),
                "allowedHosts": ["api.github.com"],
            }
        }
        captured = []
        original_run = self.module.subprocess.run

        def capture(command, **kwargs):
            if command[0] == str(self.runtime) and command[1] == "run":
                captured.append(
                    (
                        kwargs["env"]["GITHUB_TOKEN"],
                        json.loads(
                            Path(command[command.index("--conf") + 1]).read_text()
                        ),
                    )
                )
                kwargs["env"] = {
                    key: value
                    for key, value in kwargs["env"].items()
                    if key != "GITHUB_TOKEN"
                }
            return original_run(command, **kwargs)

        with mock.patch.object(self.module.subprocess, "run", side_effect=capture):
            self.assertEqual(self.launch(), 0)
        value, config = captured[0]
        self.assertEqual(value, "private-test-token")
        self.assertEqual(config["secrets"]["GITHUB_TOKEN"]["value"], "${GITHUB_TOKEN}")
        self.assertEqual(
            config["secrets"]["GITHUB_TOKEN"]["substitution"]["header_fields"],
            ["authorization"],
        )
        self.assertNotIn("private-test-token", self.log.read_text())
        self.assertNotIn("private-test-token", json.dumps(config))
        for record in self.records():
            if record["args"][0] != "run":
                self.assertNotIn("GITHUB_TOKEN", record["env"])

    def test_busy_project_state_is_refused_before_startup(self):
        self.launch()
        self.log.unlink()
        locks = list(Path(self.config["stateDir"]).glob("locks/*"))
        self.assertEqual(len(locks), 1)
        with locks[0].open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            with self.assertRaisesRegex(ValueError, "already in use"):
                self.launch()
        self.assertFalse(self.log.exists())

    def test_cleanup_timeout_still_attempts_force_stop_and_removal(self):
        original = self.module.subprocess.run

        def timeout(command, **kwargs):
            if command[1] == "stop" and "--timeout" in command:
                raise subprocess.TimeoutExpired(command, 15)
            return original(command, **kwargs)

        with mock.patch.object(self.module.subprocess, "run", side_effect=timeout):
            self.assertEqual(self.launch(), 0)
        records = self.records()
        self.assertEqual(records[-2]["args"][0:2], ["stop", "--force"])
        self.assertEqual(records[-1]["args"][0], "rm")

    def test_secret_bindings_cannot_override_host_runtime_controls(self):
        source = self.root / "secret"
        source.write_text("token")
        for name in [
            "HOME",
            "PATH",
            "LD_PRELOAD",
            "MSB_BACKEND",
            "PYTHONPATH",
            "SSL_CERT_FILE",
            "HTTPS_PROXY",
            "BASH_ENV",
            "ENV",
            "SHELLOPTS",
        ]:
            with self.subTest(name=name), self.assertRaises(ValueError):
                self.module.secret_configuration(
                    {
                        name: {
                            "sourceFile": str(source),
                            "allowedHosts": ["api.example.com"],
                        }
                    }
                )

    def test_termination_signal_runs_cleanup_and_returns_signal_status(self):
        manifest = self.root / "manifest.json"
        manifest.write_text(json.dumps(self.config))
        original = self.module.subprocess.run

        def terminate(command, **kwargs):
            if command[1] == "run":
                handler = signal.getsignal(signal.SIGTERM)
                self.assertTrue(callable(handler), "SIGTERM must trigger VM cleanup")
                handler(signal.SIGTERM, None)
            return original(command, **kwargs)

        with (
            mock.patch.object(
                sys,
                "argv",
                ["pi-sandbox", "--config", str(manifest), "--project", str(self.repo)],
            ),
            mock.patch.object(self.module, "check_kvm"),
            mock.patch.object(self.module.subprocess, "run", side_effect=terminate),
            contextlib.redirect_stderr(io.StringIO()),
        ):
            self.assertEqual(self.module.main(), 143)
        self.assertEqual(self.records()[-1]["args"][0], "rm")

    def test_bound_token_file_cannot_be_inside_a_shared_project(self):
        token = self.repo / "host-token"
        token.write_text("synthetic-host-token")
        self.config["secretBindings"] = {
            "GITHUB_TOKEN": {
                "sourceFile": str(token),
                "allowedHosts": ["api.github.com"],
            }
        }
        with self.assertRaises(ValueError):
            self.launch()
        self.assertFalse(self.log.exists())

    def test_custom_credential_paths_cannot_be_shared_as_projects(self):
        self.config["protectedPaths"] = [str(self.repo / "runtime-token")]
        with self.assertRaises(ValueError):
            self.launch()
        self.assertFalse(self.log.exists())

    def test_https_allowlist_enables_tls_inspection(self):
        self.config["allowedHosts"] = ["api.example.com"]
        self.assertEqual(self.launch(), 0)
        run = next(row for row in self.records() if row["args"][0] == "run")
        self.assertTrue(run["config"]["network"].get("tls", {}).get("enabled", False))

    def test_diagnose_does_not_boot_or_import_an_image(self):
        self.options.diagnose = True
        with contextlib.redirect_stdout(io.StringIO()) as output:
            self.assertEqual(self.launch(), 0)
        report = json.loads(output.getvalue())
        self.assertEqual(report["project"], str(self.repo))
        self.assertFalse(self.log.exists())


if __name__ == "__main__":
    unittest.main()
