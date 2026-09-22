"""Verify generated OpenSpec skills and commands for OpenCode."""

import json
from pathlib import Path
import sys


WORKFLOWS = {
    "propose": "openspec-propose",
    "explore": "openspec-explore",
    "apply": "openspec-apply-change",
    "update": "openspec-update-change",
    "sync": "openspec-sync-specs",
    "archive": "openspec-archive-change",
}
SKILL_ROOTS = (".config/opencode/skills",)


def verify(files):
    expected = {f"{root}/{name}" for root in SKILL_ROOTS for name in WORKFLOWS.values()}
    for workflow in WORKFLOWS:
        expected.add(f".config/opencode/commands/opsx-{workflow}.md")
    assert set(files) == expected, f"Missing: {expected - files.keys()}; extra: {files.keys() - expected}"

    for target, source in files.items():
        path = Path(source)
        if "/skills/" in target:
            content = (path / "SKILL.md").read_text()
            assert content.startswith("---\n"), target
            header = content.split("---", 2)[1]
            assert f"name: {Path(target).name}\n" in header, target
        else:
            content = path.read_text()
            assert content.startswith("---\n") and "description:" in content, target
        assert "openspec" in content.lower(), target
        assert "/build/" not in content and "openspec-agent-probe-" not in content, target


for manifest in json.loads(Path(sys.argv[1]).read_text()):
    verify(manifest)
print("PASS: six OpenSpec workflows for OpenCode on both hosts")
