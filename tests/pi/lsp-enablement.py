"""Real Pi: /lsp enablement persists without ever writing the Nix-managed settings.json.

The managed settings live in a read-only directory, like /nix/store: nothing can be created
beside them, so an atomic write to settings.json fails with EACCES. Durable global choices must
land in a writable file in the agent directory instead. No provider or model is involved.
"""
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

pi, fixture_file = sys.argv[1:3]
fixture = json.loads(Path(fixture_file).read_text())
root = Path(tempfile.mkdtemp(prefix="pi-lsp-enable-"))
managed_dir = root / "managed"
agent, project, home = root / "agent", root / "project", root / "home"
for directory in [managed_dir, agent, project, home]:
    directory.mkdir()
managed = managed_dir / "settings.json"
managed.write_text(json.dumps({"lsp": fixture["settings"], "extensions": [fixture["entry"]], "retry": {"enabled": False},
                               "compaction": {"enabled": False}, "quietStartup": "header"}))
original = managed.read_bytes()
managed.chmod(0o444)
managed_dir.chmod(0o555)
(agent / "settings.json").symlink_to(managed)
(project / "go.mod").write_text("module example.com/fixture\n\ngo 1.26\n")
(project / "main.go").write_text("package main\n\nfunc main() {}\n")
env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(root), "XDG_CACHE_HOME": str(home / "cache"),
       "XDG_CONFIG_HOME": str(home / "config"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
       "TERM": "xterm-256color", "LANG": "C.UTF-8", "SHELL": "/bin/sh"}
overlay = agent / "lsp-enablement.json"


def lsp(command):
    """Run one /lsp command in a fresh Pi process; Pi reports command notices on stderr."""
    result = subprocess.run([pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates",
                             "--no-mcp", "--no-session", "--mode", "json", "-p", command],
                            cwd=project, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, (command, result.returncode, result.stderr, result.stdout[-2000:])
    return result.stderr


def status():
    rows = {}
    for line in lsp("/lsp").splitlines():
        match = re.match(r"^(?:LSP servers: )?(\S+) — \S+ — (enabled|disabled) \((\w+)\)", line)
        if match:
            rows[match[1]] = (match[2], match[3])
    return rows


try:
    message = lsp("/lsp enable gopls --global")
    assert "gopls enabled at global scope" in message and "EACCES" not in message, message
    assert json.loads(overlay.read_text()) == {"lsp": {"enablement": {"gopls": True}}}, overlay.read_text()
    message = lsp("/lsp disable ruff --global")
    assert "ruff disabled at global scope" in message, message
    assert json.loads(overlay.read_text()) == {"lsp": {"enablement": {"gopls": True, "ruff": False}}}
    # Nix keeps ownership: the managed file, its symlink and its directory are untouched.
    assert (agent / "settings.json").is_symlink() and os.readlink(agent / "settings.json") == str(managed)
    assert managed.read_bytes() == original and sorted(p.name for p in managed_dir.iterdir()) == ["settings.json"]
    # A choice made by one process is effective in the next, and only for the servers chosen.
    rows = status()
    assert rows["ruff"] == ("disabled", "global") and rows["gopls"] == ("enabled", "global"), rows
    assert all(state == ("enabled", "default") for name, state in rows.items() if name not in ["ruff", "gopls"]), rows
    print("PASS: /lsp global enable/disable persist in lsp-enablement.json; managed settings untouched; choices survive restarts")
    # A damaged overlay is reported by name and ignored; it never takes LSP down.
    good = overlay.read_text()
    overlay.write_text("{ not json")
    output = lsp("/lsp")
    assert "lsp-enablement.json" in output, output
    assert all(state == ("enabled", "default") for state in status().values()), "damaged overlay must change nothing"
    overlay.write_text(good)
    assert status()["ruff"] == ("disabled", "global")
    print("PASS: a damaged lsp-enablement.json is reported by name and ignored")
finally:
    managed_dir.chmod(0o755)
