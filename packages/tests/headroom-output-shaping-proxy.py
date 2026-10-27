"""Check stable-channel shaping in requests forwarded by the real proxy."""

import argparse
import copy
import json
import os
import socket
import subprocess
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--headroom", required=True)
    args = parser.parse_args()
    calls = []

    class Upstream(BaseHTTPRequestHandler):
        def log_message(self, format, *args):
            pass

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            calls.append((self.path, self.headers.get("Authorization"), body))
            response = {
                "id": "fixture",
                "object": "chat.completion",
                "model": "fixture-model",
                "choices": [
                    {
                        "index": 0,
                        "message": {"role": "assistant", "content": "OK"},
                        "finish_reason": "stop",
                    }
                ],
                "usage": {
                    "prompt_tokens": 20,
                    "completion_tokens": 1,
                    "total_tokens": 21,
                },
            }
            if self.path.endswith("/responses"):
                response = {
                    "id": "fixture",
                    "object": "response",
                    "status": "completed",
                    "model": "fixture-model",
                    "output": [],
                    "usage": {
                        "input_tokens": 20,
                        "output_tokens": 1,
                        "total_tokens": 21,
                    },
                }
            encoded = json.dumps(response).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)

    def request(base, path, body=None):
        req = urllib.request.Request(
            base + path,
            data=None if body is None else json.dumps(body).encode(),
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer fixture-key",
            },
        )
        with urllib.request.urlopen(req, timeout=20) as response:
            return json.load(response)

    with tempfile.TemporaryDirectory(prefix="headroom-shaping-") as directory:
        root = Path(directory)
        upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
        threading.Thread(target=upstream.serve_forever, daemon=True).start()
        origin = f"http://127.0.0.1:{upstream.server_port}"
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        base = f"http://127.0.0.1:{port}"
        env = {
            k: v
            for k, v in os.environ.items()
            if not k.startswith(("HEADROOM_", "OPENCODE_", "LLM_PLATFORM_"))
        }
        for name in (
            "HOME",
            "XDG_CONFIG_HOME",
            "XDG_CACHE_HOME",
            "XDG_DATA_HOME",
            "XDG_STATE_HOME",
            "XDG_RUNTIME_DIR",
        ):
            location = root / name.lower()
            location.mkdir()
            env[name] = str(location)
        env.update(
            HEADROOM_ALLOWED_BASE_URLS=origin,
            HEADROOM_ROLLOUT_CHANNEL="stable",
            HEADROOM_OUTPUT_SHAPER="1",
            HEADROOM_VERBOSITY_LEVEL="3",
            HEADROOM_VERBOSITY_AUTOTUNE="0",
            HEADROOM_OUTPUT_HOLDOUT="0",
            HEADROOM_MODE="cache",
            HEADROOM_DISABLE_KOMPRESS="1",
            HEADROOM_OFFLINE="1",
            HEADROOM_TELEMETRY="off",
            HF_HUB_OFFLINE="1",
            TRANSFORMERS_OFFLINE="1",
            NO_PROXY="127.0.0.1,localhost",
        )
        with (root / "proxy.log").open("w+") as log:
            process = subprocess.Popen(
                [
                    args.headroom,
                    "proxy",
                    "--port",
                    str(port),
                    "--stateless",
                    "--no-cache",
                    "--no-rate-limit",
                    "--no-subscription-tracking",
                    "--openai-api-url",
                    origin,
                ],
                cwd=root,
                env=env,
                stdout=log,
                stderr=log,
            )
            try:
                for _ in range(300):
                    if process.poll() is not None:
                        raise AssertionError("Proxy exited before becoming ready")
                    try:
                        request(base, "/health")
                        break
                    except (OSError, urllib.error.URLError):
                        time.sleep(0.1)
                else:
                    raise AssertionError("Proxy readiness timeout")
                original_system = "Keep the repository conventions."
                chat = {
                    "model": "fixture-model",
                    "messages": [
                        {"role": "system", "content": original_system},
                        {"role": "user", "content": "Reply OK."},
                    ],
                    "reasoning_effort": "high",
                    "max_completion_tokens": 8192,
                    "stream": False,
                }
                request(base, "/v1/chat/completions", chat)
                forwarded = calls[-1][2]
                system = "\n".join(
                    message["content"]
                    for message in forwarded["messages"]
                    if message["role"] == "system"
                )
                assert original_system in system and len(system) > len(
                    original_system
                ), forwarded
                assert forwarded["reasoning_effort"] == "high", forwarded
                assert forwarded["max_completion_tokens"] == 8192, forwarded
                repeat = copy.deepcopy(chat)
                repeat["messages"] = forwarded["messages"]
                request(base, "/v1/chat/completions", repeat)
                assert calls[-1][2]["messages"] == forwarded["messages"], calls[-1][2]
                responses = {
                    "model": "fixture-model",
                    "instructions": original_system,
                    "input": [{"role": "user", "content": "Reply OK."}],
                    "reasoning": {"effort": "high"},
                    "max_output_tokens": 8192,
                    "stream": False,
                }
                request(base, "/v1/responses", responses)
                forwarded = calls[-1][2]
                assert original_system in forwarded["instructions"] and len(
                    forwarded["instructions"]
                ) > len(original_system), forwarded
                assert forwarded["reasoning"] == {"effort": "high"}, forwarded
                assert forwarded["max_output_tokens"] == 8192, forwarded
                repeat = copy.deepcopy(responses)
                repeat["instructions"] = forwarded["instructions"]
                request(base, "/v1/responses", repeat)
                assert calls[-1][2]["instructions"] == forwarded["instructions"], calls[
                    -1
                ][2]
                assert all(auth == "Bearer fixture-key" for _, auth, _ in calls), calls
                print(
                    "Stable L3 steering forwarded for Chat and Responses; controls and repeated prefixes preserved"
                )
            except BaseException:
                log.flush()
                log.seek(0)
                print(log.read()[-6000:])
                raise
            finally:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait(timeout=10)
                upstream.shutdown()
                upstream.server_close()


if __name__ == "__main__":
    main()
