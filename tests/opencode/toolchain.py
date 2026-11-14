#!/usr/bin/env python3
"""Contract check for OpenCode's LSP servers and formatters (generated from the Nix config)."""
import json
import os
import subprocess
import sys

settings_path = sys.argv[1]
fixdir = sys.argv[2]
os.makedirs(fixdir, exist_ok=True)

with open(settings_path) as f:
    settings = json.load(f)

# --- LSP servers: binary exists and is executable ---
for name, entry in (settings.get("lsp") or {}).items():
    if entry.get("disabled"):
        continue
    cmd = entry.get("command") or []
    if not cmd:
        raise SystemExit(f"LSP {name}: missing command")
    binary = cmd[0]
    if not os.path.isfile(binary) or not os.access(binary, os.X_OK):
        raise SystemExit(f"LSP {name}: binary not executable: {binary}")
    # Probe: anything but "command not found" (127) or a timeout means it runs.
    try:
        subprocess.run([binary, "--help"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                       stderr=subprocess.DEVNULL, timeout=10, check=False)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"LSP {name}: --help timed out: {binary}")

# --- Formatters: in-place contract + marker gating ---
SAMPLES = {
    ".go": "package main\nfunc main( ) {\n}\n",
    ".json": '{"a":1}',
    ".nix": "{a=1;}",
    ".py": "x=1\n",
    ".pyi": "x=1\n",
    ".lua": "local x=1\n",
    ".sh": "if true;then\necho hi\nfi\n",
    ".bash": "if true;then\necho hi\nfi\n",
    ".rs": "fn main(){ }\n",
    ".zig": "const x=1;\n",
    ".zon": "const x=1;\n",
    ".tf": 'resource "x" "y" {\n  a=1\n}\n',
    ".tfvars": "a=1\n",
    ".ts": "let a=1\n",
    ".tsx": "let a=1\n",
    ".js": "let a=1\n",
    ".jsx": "let a=1\n",
    ".mts": "let a=1\n",
    ".cts": "let a=1\n",
    ".mjs": "let a=1\n",
    ".cjs": "let a=1\n",
    ".md": "# a\n",
}

for name, entry in (settings.get("formatter") or {}).items():
    if entry.get("disabled"):
        continue
    command = entry.get("command") or []
    extensions = entry.get("extensions") or []
    if not command or not extensions:
        raise SystemExit(f"formatter {name}: missing command or extensions")
    if command[-1] != "$FILE":
        raise SystemExit(f"formatter {name}: command must end in $FILE, got {command}")
    ext = extensions[0]
    sample = SAMPLES.get(ext)
    if sample is None:
        raise SystemExit(f"formatter {name}: no sample for {ext}")
    markers = []  # marker list lives in the wrapper, not the schema; infer from name
    # shfmt and biome are marker-gated in our config; test both paths.
    marker_gated = name in ("shfmt", "biome")
    marker_files = { "shfmt": [".editorconfig"], "biome": ["biome.json"] }.get(name, [])

    # --- no-marker path: must not change the file ---
    work = os.path.join(fixdir, f"nomarker-{name}")
    os.makedirs(work, exist_ok=True)
    fixture = os.path.join(work, f"sample{ext}")
    with open(fixture, "w") as f:
        f.write(sample)
    before = open(fixture).read()
    cmd = [c if c != "$FILE" else fixture for c in command]
    r = subprocess.run(cmd, cwd=work, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    after = open(fixture).read()
    if marker_gated:
        if r.returncode == 0:
            raise SystemExit(f"formatter {name}: succeeded without marker (should skip)")
        if before != after:
            raise SystemExit(f"formatter {name}: changed file without marker (should be a no-op)")
    else:
        if r.returncode != 0:
            raise SystemExit(f"formatter {name}: failed: {r.stderr.decode(errors='replace')[:300]}")
        if before == after:
            raise SystemExit(f"formatter {name}: did not change the file")

    # --- marker path (marker-gated only) ---
    if marker_gated:
        work2 = os.path.join(fixdir, f"marker-{name}")
        os.makedirs(work2, exist_ok=True)
        fixture2 = os.path.join(work2, f"sample{ext}")
        with open(fixture2, "w") as f:
            f.write(sample)
        for m in marker_files:
            with open(os.path.join(work2, m), "w") as f:
                f.write("{}" if m.endswith(".json") else "")
        before2 = open(fixture2).read()
        cmd2 = [c if c != "$FILE" else fixture2 for c in command]
        r2 = subprocess.run(cmd2, cwd=work2, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        after2 = open(fixture2).read()
        if r2.returncode != 0:
            raise SystemExit(f"formatter {name}: failed with marker: {r2.stderr.decode(errors='replace')[:300]}")
        if before2 == after2:
            raise SystemExit(f"formatter {name}: did not change the file with marker")

# --- Permissions / snapshots / todo ---
perms = settings.get("permissions") or []
if not any(p.get("action") == "read" and p.get("resource") == "*.env" and p.get("effect") == "deny" for p in perms):
    raise SystemExit("permissions: missing read *.env deny rule")
if settings.get("snapshots") is not True:
    raise SystemExit("snapshots must be true")
if (settings.get("experimental") or {}).get("todo") is not True:
    raise SystemExit("experimental.todo must be true")

print("opencode toolchain OK")
