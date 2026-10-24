#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import sys
import tempfile

root = Path(tempfile.mkdtemp(prefix="pi-mcp-real-", dir=os.environ.get("TMPDIR", "/tmp/opencode")))
for name in ["home", "runtime", "tmp", "project"]:
    (root / name).mkdir(mode=0o700)
(root / "project/main.py").write_text("def fixture():\n    return 1\n")
subprocess.run(["git", "init", "-q", "-b", "main"], cwd=root / "project", check=True)
env = {
    "PATH": os.environ["PATH"], "HOME": str(root / "home"),
    "XDG_RUNTIME_DIR": str(root / "runtime"), "XDG_CONFIG_HOME": str(root / "home/.config"),
    "TMPDIR": str(root / "tmp"), "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN": "synthetic-fixture-only",
    "UV_CACHE_DIR": "/tmp/opencode/pi-serena-cache", "HEADROOM_TELEMETRY": "off",
    "HEADROOM_DISABLE_KOMPRESS": "1", "HF_HUB_OFFLINE": "1", "TRANSFORMERS_OFFLINE": "1",
    "PYTHONPATH": "/SYNTHETIC_FOREIGN_PYTHONPATH", "PYTHONHOME": "/SYNTHETIC_FOREIGN_PYTHONHOME",
}
print("Fixture:", root, flush=True)
binary = Path(sys.argv[1]).resolve()
result = subprocess.run([str(binary)], cwd=root / "project", env=env, text=True, capture_output=True, timeout=240)
(root / "stdout.log").write_text(result.stdout)
(root / "stderr.log").write_text(result.stderr)
print(result.stdout)
print(result.stderr)
raise SystemExit(result.returncode)
