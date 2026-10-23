"""Pi's settings.json is a writable copy of the Nix settings, replaced again on every switch.

Real Pi and the real installer; nothing is mocked. The migration source is a settings file in a
read-only directory, like the symlink target an earlier generation left in /nix/store.

usage: writable-settings.py PI CONTRACT_JSON   (CONTRACT_JSON: installer, settingsFile and the other managed files)
"""
import json
import os
import re
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

pi, contract_arg = sys.argv[1:3]
contract = json.loads(Path(contract_arg).read_text())
installer = contract["installer"]
managed = Path(contract["settingsFile"])
managed_bytes = managed.read_bytes()
root = Path(tempfile.mkdtemp(prefix="pi-settings-"))
home = root / "home"
agent = home / ".pi/agent"
target = agent / "settings.json"
backup = agent / "settings.json.replaced"


def install(source=managed):
    return subprocess.run([installer, str(source), str(target)], capture_output=True, text=True, timeout=60)


def regular_and_writable(path):
    info = os.lstat(path)
    return stat.S_ISREG(info.st_mode) and bool(info.st_mode & stat.S_IWUSR)


# A fresh machine: neither the file nor its directory exists.
result = install()
assert result.returncode == 0, result
assert regular_and_writable(target) and target.read_bytes() == managed_bytes
assert stat.S_IMODE(os.lstat(target).st_mode) == 0o644 and not backup.exists()

# Already exactly the Nix settings: nothing is rewritten.
before = os.stat(target)
assert install().returncode == 0
after = os.stat(target)
assert (before.st_ino, before.st_mtime_ns) == (after.st_ino, after.st_mtime_ns) and not backup.exists()

# Runtime edits are discarded by a switch, but the replaced file is kept once for recovery.
runtime = json.loads(managed_bytes)
runtime["defaultThinkingLevel"] = "low"
runtime["lastChangelogVersion"] = "9.9.9"
target.write_text(json.dumps(runtime))
result = install()
assert result.returncode == 0 and target.read_bytes() == managed_bytes, result
assert json.loads(backup.read_text())["lastChangelogVersion"] == "9.9.9"
assert "settings.json.replaced" in result.stderr, result.stderr
backup.unlink()

# Migration: an earlier generation linked settings.json into a read-only store directory.
store = root / "store"
store.mkdir()
old = store / "old-settings.json"
old.write_text(json.dumps({"defaultThinkingLevel": "old"}))
old.chmod(0o444)
store.chmod(0o555)
target.unlink()
target.symlink_to(old)
result = install()
assert result.returncode == 0, result
assert regular_and_writable(target) and target.read_bytes() == managed_bytes
assert json.loads(old.read_text()) == {"defaultThinkingLevel": "old"} and not backup.exists(), "the old target must be left alone"
store.chmod(0o755)

# Failures are loud and leave the current file alone.
result = install(root / "does-not-exist.json")
assert result.returncode != 0 and target.read_bytes() == managed_bytes, result
blocked = root / "blocked" / "settings.json"
blocked.mkdir(parents=True)
result = subprocess.run([installer, str(managed), str(blocked)], capture_output=True, text=True, timeout=60)
assert result.returncode != 0 and blocked.is_dir(), result
print("PASS installer: fresh install, no-op when identical, runtime edits replaced with one recovery copy, store symlink migrated, failures leave the file alone", flush=True)

# Real Pi can now persist what its commands and extensions persist.
project = root / "project"
project.mkdir()
env = {"PATH": os.environ["PATH"], "HOME": str(home), "TMPDIR": str(root), "XDG_CACHE_HOME": str(home / ".cache"),
       "XDG_CONFIG_HOME": str(home / ".config"), "PI_CODING_AGENT_DIR": str(agent), "PI_OFFLINE": "1", "PI_TELEMETRY": "0",
       "TERM": "xterm-256color", "LANG": "C.UTF-8", "SHELL": "/bin/sh"}


def pi_command(command):
    result = subprocess.run([pi, "--offline", "--no-approve", "--no-context-files", "--no-skills", "--no-prompt-templates",
                             "--no-mcp", "--no-session", "--mode", "json", "-p", command],
                            cwd=project, env=env, capture_output=True, text=True, timeout=180)
    assert result.returncode == 0, (command, result.returncode, result.stderr, result.stdout[-2000:])
    assert "EACCES" not in result.stderr + result.stdout, (command, result.stderr, result.stdout[-2000:])
    return result.stderr + result.stdout


def settings():
    return json.loads(target.read_text())


assert install().returncode == 0
for name, source in contract["files"].items():  # every other managed file stays a store symlink
    if name != "settings.json":
        (agent / name).parent.mkdir(parents=True, exist_ok=True)
        (agent / name).symlink_to(source)
output = pi_command("/lsp enable gopls --global")
assert "gopls enabled at global scope" in output, output
assert settings()["lsp"]["enablement"] == {"gopls": True} and settings()["extensions"] == json.loads(managed_bytes)["extensions"]
output = pi_command("/subagents-watchdog on")
assert re.search(r"watchdog.*saved to user settings", output, re.I | re.S), output
assert settings()["subagents"]["watchdog"]["enabled"] is True and settings()["subagents"]["disableBuiltins"] is True
assert "gopls — configured — enabled (global)" in pi_command("/lsp"), "a global choice must survive into the next Pi process"

# A switch resets everything to the Nix settings and keeps one copy of what was replaced.
result = install()
assert result.returncode == 0 and target.read_bytes() == managed_bytes, result
replaced = json.loads(backup.read_text())
assert replaced["lsp"]["enablement"] == {"gopls": True} and replaced["subagents"]["watchdog"]["enabled"] is True
assert "gopls — configured — enabled (default)" in pi_command("/lsp"), "after a switch the Nix settings alone decide"
print("PASS real Pi: /lsp --global and /subagents-watchdog persist without EACCES; a switch resets to the Nix settings", flush=True)
