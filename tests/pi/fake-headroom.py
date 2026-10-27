#!/usr/bin/env python3
"""Process-boundary fixture; no production services or real credentials."""

import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time
import uuid
from http.server import BaseHTTPRequestHandler, HTTPServer

mode = sys.argv[1]
if mode == "verify-proxy-env":
    if os.environ.get("PYTHONPATH") or os.environ.get("PYTHONHOME"):
        sys.exit(73)
    sys.argv.pop(1)
    mode = sys.argv[1]
if mode == "verify-memory-policy":
    if "--no-memory-tools" not in sys.argv:
        sys.exit(74)
    if "--memory" in sys.argv:
        sys.exit(75)
    sys.argv.pop(1)
    mode = sys.argv[1]
if mode == "proxy":
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, required=True)
    args, _ = parser.parse_known_args(sys.argv[2:])
    if os.environ.get("FIXTURE_PROXY_CWD"):
        Path(os.environ["FIXTURE_PROXY_CWD"]).write_text(os.getcwd())
    if os.environ.get("FIXTURE_PROXY_ARGS"):
        Path(os.environ["FIXTURE_PROXY_ARGS"]).write_text(json.dumps(sys.argv[2:]))

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            data = json.dumps(
                {"status": "ok", "config": {"memory": True, "code_graph": False}}
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(data)

        def log_message(self, *args):
            pass

    HTTPServer(("127.0.0.1", args.port), Handler).serve_forever()
elif mode == "pi":
    parser = argparse.ArgumentParser()
    parser.add_argument("--capture", required=True)
    parser.add_argument("--until")
    parser.add_argument("--exit", type=int, default=0)
    parser.add_argument("--spawn-worker", action="store_true")
    args = parser.parse_args(sys.argv[2:])
    Path(args.capture).write_text(
        json.dumps(
            {
                key: os.environ.get(key)
                for key in [
                    "HEADROOM_PROXY_URL",
                    "LLM_PLATFORM_INFERENCE_PROXY_URL",
                    "LLM_PLATFORM_INFERENCE_PROXY_REQUIRED",
                    "HEADROOM_PI_STATE_DIR",
                    "HEADROOM_PI_MEMORY_DB",
                    "PYTHONPATH",
                    "PYTHONHOME",
                ]
            }
        )
    )
    if args.spawn_worker:
        directory = (
            Path(os.environ["PI_SUBAGENTS_TEMP_ROOT"]) / "async-subagent-runs/fixture"
        )
        directory.mkdir(parents=True, mode=0o700)
        marker = (
            Path(os.environ["HEADROOM_PI_STATE_DIR"])
            / "leases"
            / (str(uuid.uuid4()) + ".json")
        )
        marker.write_text(
            json.dumps(
                {
                    "instance": os.environ["HEADROOM_PI_INSTANCE"],
                    "kind": "run",
                    "statePath": str(directory / "status.json"),
                    "deadline": time.time() * 1000 + 5000,
                }
            )
        )
        subprocess.Popen(
            [sys.executable, "-E", __file__, "worker", str(directory / "status.json")],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
    while args.until and not Path(args.until).exists():
        time.sleep(0.02)
    sys.exit(args.exit)
elif mode == "worker":
    path = Path(sys.argv[2])
    time.sleep(0.3)
    path.write_text(json.dumps({"state": "running", "pid": os.getpid()}))
    time.sleep(0.7)
    path.write_text(json.dumps({"state": "complete", "pid": os.getpid()}))
