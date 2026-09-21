"""Verify generated OpenSpec integrations, including tool-specific command formats."""

import json
from pathlib import Path
import sys
import tomllib


WORKFLOWS = {
    "propose": "openspec-propose",
    "explore": "openspec-explore",
    "apply": "openspec-apply-change",
    "update": "openspec-update-change",
    "sync": "openspec-sync-specs",
    "archive": "openspec-archive-change",
}
SKILL_ROOTS = (
    ".codex/skills",
    ".config/opencode/skills",
    ".gemini/skills",
    ".gemini/antigravity-cli/skills",
    ".cursor/skills",
)


def verify(files):
    expected = {f"{root}/{name}" for root in SKILL_ROOTS for name in WORKFLOWS.values()}
    for workflow in WORKFLOWS:
        expected.update(
            (
                f".config/opencode/commands/opsx-{workflow}.md",
                f".gemini/commands/opsx/{workflow}.toml",
                f".cursor/commands/opsx-{workflow}.md",
            )
        )
    assert set(files) == expected, f"Missing: {expected - files.keys()}; extra: {files.keys() - expected}"

    for target, source in files.items():
        path = Path(source)
        if "/skills/" in target:
            content = (path / "SKILL.md").read_text()
            assert content.startswith("---\n"), target
            header = content.split("---", 2)[1]
            assert f"name: {Path(target).name}\n" in header, target
        elif target.endswith(".toml"):
            command = tomllib.loads(path.read_text())
            assert command["description"] and command["prompt"], target
            content = command["prompt"]
        else:
            content = path.read_text()
            assert content.startswith("---\n") and "description:" in content, target
        assert "openspec" in content.lower(), target
        assert "/build/" not in content and "openspec-agent-probe-" not in content, target

    antigravity = Path(files[".gemini/antigravity-cli/skills/openspec-propose"])
    assert "/openspec-apply-change" in (antigravity / "SKILL.md").read_text()
    codex = Path(files[".codex/skills/openspec-propose"])
    assert "$openspec-apply-change" in (codex / "SKILL.md").read_text()


for manifest in json.loads(Path(sys.argv[1]).read_text()):
    verify(manifest)
print("PASS: six OpenSpec workflows across five agents on both hosts")
