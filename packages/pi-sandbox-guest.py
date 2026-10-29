import json
import os
import shutil
import sys
import tempfile
from pathlib import Path, PurePosixPath


def managed_names(value):
    if not isinstance(value, list):
        raise ValueError("Managed-file manifest must be a list")
    for name in value:
        if not isinstance(name, str):
            raise ValueError("Invalid managed-file name")
        relative = PurePosixPath(name)
        if relative.is_absolute() or ".." in relative.parts or not relative.parts:
            raise ValueError("Managed files must stay inside the guest agent directory")
        if relative.parts[0] in {
            "auth.json",
            "mcp-auth.json",
            "sessions",
            ".pi-sandbox-managed.json",
        }:
            raise ValueError(
                "Guest credentials and sessions cannot be managed defaults"
            )
    return value


def destination(root, name):
    relative = PurePosixPath(name)
    parent = root
    for part in relative.parts[:-1]:
        parent = parent / part
        if parent.is_symlink():
            raise ValueError("Managed configuration parents cannot be symlinks")
        parent.mkdir(mode=0o700, exist_ok=True)
    return root / name


def replace_file(target, source=None, content=None):
    descriptor, temporary = tempfile.mkstemp(prefix=".pi-sandbox-", dir=target.parent)
    try:
        with os.fdopen(descriptor, "wb") as stream:
            if source is not None:
                with source.open("rb") as original:
                    shutil.copyfileobj(original, stream)
            else:
                stream.write(content)
        os.replace(temporary, target)
    finally:
        Path(temporary).unlink(missing_ok=True)


def refresh(source, target):
    if target.is_symlink():
        raise ValueError("Guest agent directory cannot be a symlink")
    target.mkdir(mode=0o700, parents=True, exist_ok=True)
    current = managed_names(json.loads((source / "manifest.json").read_text()))
    ledger = target / ".pi-sandbox-managed.json"
    previous = managed_names(json.loads(ledger.read_text())) if ledger.exists() else []
    for name in current:
        replace_file(destination(target, name), source=source / name)
    for name in set(previous) - set(current):
        destination(target, name).unlink(missing_ok=True)
    replace_file(ledger, content=json.dumps(current).encode())


if __name__ == "__main__":
    try:
        refresh(Path(sys.argv[1]), Path(sys.argv[2]))
    except (ValueError, OSError) as error:
        print(f"pi-sandbox-guest: {error}", file=sys.stderr)
        sys.exit(1)
