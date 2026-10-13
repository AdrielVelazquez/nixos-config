"""Check per-server Python isolation at the OpenCode launcher boundary."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
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
                    self.assertEqual(server["environment"]["SERENA_SENTINEL"], "preserved")
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


if __name__ == "__main__":
    unittest.main()
