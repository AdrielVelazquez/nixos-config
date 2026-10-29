import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(
    os.environ.get(
        "PI_SANDBOX_GUEST_TEST_SOURCE",
        Path(__file__).resolve().parents[2] / "packages" / "pi-sandbox-guest.py",
    )
)


class GuestConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.assertTrue(
            SOURCE.is_file(), "guest configuration seeding is not implemented"
        )
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        root = Path(self.temp.name)
        self.source = root / "generated"
        self.target = root / "private" / "agent"
        self.source.mkdir()
        self.target.mkdir(parents=True)

    def seed(self, files):
        (self.source / "manifest.json").write_text(json.dumps(files))
        return subprocess.run(
            [sys.executable, "-B", str(SOURCE), str(self.source), str(self.target)],
            capture_output=True,
            text=True,
        )

    def test_refreshes_defaults_preserving_guest_auth_and_sessions(self):
        (self.source / "settings.json").write_text('{"managed": true}')
        (self.target / "settings.json").write_text('{"old": true}')
        (self.target / "auth.json").write_text("guest-private-auth")
        (self.target / "sessions").mkdir()
        (self.target / "sessions" / "session.jsonl").write_text("conversation")
        self.assertEqual(self.seed(["settings.json"]).returncode, 0)
        self.assertEqual(
            json.loads((self.target / "settings.json").read_text()), {"managed": True}
        )
        self.assertEqual((self.target / "auth.json").read_text(), "guest-private-auth")
        self.assertEqual(
            (self.target / "sessions" / "session.jsonl").read_text(), "conversation"
        )

    def test_removes_only_retired_managed_files(self):
        (self.target / ".pi-sandbox-managed.json").write_text(
            json.dumps(["retired.ts"])
        )
        (self.target / "retired.ts").write_text("obsolete")
        (self.target / "personal.ts").write_text("guest-only")
        self.assertEqual(self.seed([]).returncode, 0)
        self.assertFalse((self.target / "retired.ts").exists())
        self.assertEqual((self.target / "personal.ts").read_text(), "guest-only")

    def test_replaces_symlink_without_overwriting_its_target(self):
        original = self.source / "original"
        original.write_text("immutable")
        (self.source / "settings.json").write_text("new defaults")
        (self.target / "settings.json").symlink_to(original)
        self.assertEqual(self.seed(["settings.json"]).returncode, 0)
        self.assertFalse((self.target / "settings.json").is_symlink())
        self.assertEqual(original.read_text(), "immutable")

    def test_refuses_parent_paths_in_previous_manifest(self):
        (self.target.parent / "untouched").write_text("keep")
        (self.target / ".pi-sandbox-managed.json").write_text(
            json.dumps(["../untouched"])
        )
        self.assertNotEqual(self.seed([]).returncode, 0)
        self.assertEqual((self.target.parent / "untouched").read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
