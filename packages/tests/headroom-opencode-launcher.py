"""Check per-server Python isolation at the OpenCode launcher boundary."""

import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

LAUNCHER = Path(sys.argv.pop(1))
spec = importlib.util.spec_from_file_location("launcher", LAUNCHER)
launcher = importlib.util.module_from_spec(spec)
spec.loader.exec_module(launcher)


class SerenaIsolationTests(unittest.TestCase):
    def test_serena_uses_its_own_dependencies_in_both_config_documents(self):
        # Without per-Serena isolation, the inherited module shadows its own.
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            inherited = root / "headroom-dependencies"
            isolated = root / "serena-dependencies"
            inherited.mkdir()
            isolated.mkdir()
            (inherited / "dependency.py").write_text('VERSION = "headroom"\n')
            (isolated / "dependency.py").write_text('VERSION = "serena"\n')
            command = [
                sys.executable,
                "-c",
                f"import sys; sys.path.append({str(isolated)!r}); "
                "import dependency; print(dependency.VERSION)",
            ]
            config = {
                "providers": {"llmplatform": {}},
                "mcp": {
                    "servers": {
                        "serena": {
                            "type": "local",
                            "command": command,
                            "environment": {"SERENA_SENTINEL": "preserved"},
                        },
                        "headroom": {"type": "local", "command": command},
                    }
                },
            }
            inline = {
                "providers": {
                    "headroom": {"settings": {"baseURL": "http://localhost:8787/v1"}}
                },
                "mcp": {
                    "serena": {
                        "type": "local",
                        "command": command,
                        "environment": {"SERENA_SENTINEL": "preserved"},
                    }
                },
            }
            config_path = root / "opencode.json"
            config_path.write_text(json.dumps(config))
            environment = {
                **os.environ,
                "OPENCODE_CONFIG": str(config_path),
                "OPENCODE_CONFIG_CONTENT": json.dumps(inline),
                "PYTHONPATH": str(inherited),
                "PYTHONHOME": sys.base_prefix,
                "HEADROOM_OPENCODE_NO_SERENA": "0",
            }
            # Replace only process handoff; run all translation/config writes.
            with (
                patch.dict(os.environ, environment, clear=True),
                patch.object(sys, "argv", [str(LAUNCHER), "/unused/opencode"]),
                patch.object(os, "execv"),
            ):
                launcher.main()
                documents = [
                    json.loads(config_path.read_text()),
                    json.loads(os.environ["OPENCODE_CONFIG_CONTENT"]),
                ]
                self.assertEqual(os.environ["PYTHONPATH"], str(inherited))
                self.assertEqual(os.environ["PYTHONHOME"], sys.base_prefix)
                for document in documents:
                    server = document["mcp"]["servers"]["serena"]
                    self.assertEqual(server["command"], command)
                    self.assertEqual(
                        server["environment"]["SERENA_SENTINEL"], "preserved"
                    )
                    result = subprocess.run(
                        server["command"],
                        env={**os.environ, **server["environment"]},
                        cwd=root,
                        capture_output=True,
                        text=True,
                        check=True,
                    )
                    self.assertEqual(result.stdout.strip(), "serena")
                    self.assertEqual(server["environment"]["PYTHONHOME"], "")
                headroom = documents[0]["mcp"]["servers"]["headroom"]
                result = subprocess.run(
                    headroom["command"],
                    env={**os.environ, **headroom["environment"]},
                    cwd=root,
                    capture_output=True,
                    text=True,
                    check=True,
                )
                self.assertEqual(result.stdout.strip(), "headroom")


class LauncherArgumentsTests(unittest.TestCase):
    def _run_launcher(self, arguments, configured=True):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = root / "opencode"
            target.write_text(
                f"#!{sys.executable}\nimport json, sys\nprint(json.dumps(sys.argv[1:]))\n"
            )
            target.chmod(0o700)
            environment = {"PATH": os.defpath}
            if configured:
                config = root / "opencode.json"
                config.write_text("{}")
                environment.update(
                    OPENCODE_CONFIG=str(config),
                    OPENCODE_CONFIG_CONTENT=json.dumps(
                        {
                            "providers": {
                                "headroom": {
                                    "settings": {"baseURL": "http://127.0.0.1:8787/v1"}
                                }
                            }
                        }
                    ),
                )
            return subprocess.run(
                [sys.executable, str(LAUNCHER), str(target), *arguments],
                cwd=root,
                env=environment,
                capture_output=True,
                text=True,
                timeout=10,
                check=False,
            )

    def test_version_probe_works_before_the_launch_config_exists(self):
        result = self._run_launcher(["--version"], configured=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), ["--version"])

    def test_standalone_injection_is_idempotent_for_upstream_wrapped_arguments(self):
        for arguments, expected in [
            ([], ["--standalone"]),
            (["--standalone"], ["--standalone"]),
            (["run", "hello"], ["run", "--standalone", "hello"]),
            (["run", "--standalone", "hello"], ["run", "--standalone", "hello"]),
            (["mini", "--standalone", "hello"], ["mini", "--standalone", "hello"]),
            (
                ["run", "--", "--standalone"],
                ["run", "--standalone", "--", "--standalone"],
            ),
        ]:
            with self.subTest(arguments=arguments):
                result = self._run_launcher(arguments)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), expected)


if __name__ == "__main__":
    unittest.main()
