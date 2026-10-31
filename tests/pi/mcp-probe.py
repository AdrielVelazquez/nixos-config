#!/usr/bin/env python3
"""Initialize real declared stdio servers in an isolated project."""

import json
import os
from pathlib import Path
import re
import selectors
import signal
import subprocess
import sys
import time
import urllib.request

state = json.loads(
    (Path(os.environ["HEADROOM_PI_STATE_DIR"]) / "state.json").read_text()
)
with urllib.request.urlopen(
    os.environ["HEADROOM_PROXY_URL"] + "/health", timeout=5
) as response:
    health = json.load(response)
assert not health["config"]["code_graph"] and not health["config"]["memory"], health
assert state["graphPid"] != state["proxyPid"], state


# Linux inotify registrations prove the separate graph process started the
# upstream watcher; the shared proxy must not own project-local resources.
def watched(inode):
    for path in Path(f"/proc/{state['graphPid']}/fdinfo").iterdir():
        try:
            if any(
                f"ino:{inode:x} " in line
                for line in path.read_text().splitlines()
                if line.startswith("inotify ")
            ):
                return True
        except OSError:
            pass
    return False


assert watched(Path(state["project"]).stat().st_ino), (
    "Headroom has no inotify watch on the project root"
)
print(
    "PASS: actual Headroom graph sidecar owns the project-root inotify watch",
    flush=True,
)

servers = json.loads(Path(sys.argv[1]).read_text())["mcpServers"]
for name in ["headroom", "headroom_memory", "serena"]:
    if name not in servers or servers[name].get("enabled") is False:
        continue
    config = servers[name]
    env = dict(os.environ)
    for key, value in config.get("env", {}).items():
        env[key] = re.sub(
            r"\$\{([^}]+)\}", lambda match: os.environ.get(match[1], ""), value
        )
    log = Path(os.environ["HOME"]) / (name + ".log")
    with log.open("w") as stderr:
        child = subprocess.Popen(
            [config["command"], *config.get("args", [])],
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=stderr,
            bufsize=0,
            start_new_session=True,
        )
        try:
            counter = 0

            def send(method, params, notification=False):
                global counter
                counter += 1
                message = {"jsonrpc": "2.0", "method": method, "params": params}
                if not notification:
                    message["id"] = counter
                child.stdin.write((json.dumps(message) + "\n").encode())
                child.stdin.flush()
                if notification:
                    return
                selector = selectors.DefaultSelector()
                selector.register(child.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + 120
                while time.monotonic() < deadline:
                    if not selector.select(timeout=0.2):
                        if child.poll() is not None:
                            raise AssertionError(
                                f"{name} exited: {log.read_text()[-3000:]}"
                            )
                        continue
                    line = child.stdout.readline()
                    if not line:
                        raise AssertionError(
                            f"{name} closed stdout: {log.read_text()[-3000:]}"
                        )
                    response = json.loads(line)
                    if response.get("id") == counter:
                        selector.close()
                        assert "error" not in response, response
                        return response["result"]
                raise AssertionError(f"{name} timed out: {log.read_text()[-3000:]}")

            send(
                "initialize",
                {
                    "protocolVersion": "2025-11-25",
                    "capabilities": {},
                    "clientInfo": {"name": "pi-migration-fixture", "version": "1"},
                },
            )
            send("notifications/initialized", {}, notification=True)
            tools = send("tools/list", {})["tools"]
            names = [tool["name"] for tool in tools]
            if name == "headroom":
                assert "headroom_retrieve" in names and "headroom_stats" in names, names
            elif name == "headroom_memory":
                assert "memory_save" in names and "memory_search" in names, names
                saved = send(
                    "tools/call",
                    {
                        "name": "memory_save",
                        "arguments": {
                            "content": "Synthetic migration fixture fact: cobalt-planet-517",
                            "importance": 0.8,
                        },
                    },
                )
                assert "Saved" in json.dumps(saved) or "saved" in json.dumps(saved), (
                    saved
                )
                found = send(
                    "tools/call",
                    {
                        "name": "memory_search",
                        "arguments": {"query": "cobalt-planet-517", "top_k": 5},
                    },
                )
                assert "cobalt-planet-517" in json.dumps(found), found
            else:
                assert "find_symbol" in names and "get_symbols_overview" in names, names
            print(
                f"PASS: {name} real MCP initialization and {len(names)} tools"
                + (
                    ", persistent memory save/search"
                    if name == "headroom_memory"
                    else ""
                ),
                flush=True,
            )
        finally:
            child.stdin.close()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
