#!/usr/bin/env python3
"""Project-owned lifecycle for Headroom's live code-graph watcher."""

import argparse
import json
import os
from pathlib import Path
import signal
import threading
import uuid

from headroom.graph.watcher import CodeGraphWatcher


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", required=True)
    parser.add_argument("--ready", type=Path, required=True)
    args = parser.parse_args()
    stopped = threading.Event()
    for sig in [signal.SIGTERM, signal.SIGINT]:
        signal.signal(sig, lambda *_: stopped.set())
    watcher = CodeGraphWatcher(project_dir=Path.cwd(), cbm_binary=args.binary)
    temporary = args.ready.with_name(f".graph-ready-{uuid.uuid4()}")
    try:
        if not watcher.start():
            raise RuntimeError("Headroom project graph watcher could not start")
        with temporary.open("x") as file:
            os.chmod(temporary, 0o600)
            json.dump({"project": str(Path.cwd()), "pid": os.getpid()}, file)
        temporary.replace(args.ready)
        stopped.wait()
    finally:
        temporary.unlink(missing_ok=True)
        args.ready.unlink(missing_ok=True)
        watcher.stop()


if __name__ == "__main__":
    main()
