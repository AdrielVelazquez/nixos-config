"""Exercise native v2 catalog routing through a real Headroom proxy, offline."""

import argparse
import base64
import json
import os
import secrets
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
    parser.add_argument("--opencode", required=True)
    parser.add_argument("--headroom", required=True)
    parser.add_argument("--plugin", required=True)
    parser.add_argument("--catalog-plugin")
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="opencode-headroom-v2-"))
    calls = []
    processes = []
    logs = []

    class Upstream(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            data = [
                {
                    "id": name,
                    "owned_by": "fixture",
                    "x_llm_platform": {
                        "capabilities": {
                            "api": [api],
                            "tools": True,
                            "modalities": {"input": ["text"], "output": ["text"]},
                        }
                    },
                }
                for name, api in [
                    ("chat", "chat_completions"),
                    ("responses", "responses"),
                ]
            ]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"object": "list", "data": data}).encode())

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            calls.append((self.path, dict(self.headers), body))
            if self.path not in ("/v1/openai/responses", "/v1/openai/chat/completions"):
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()

            def event(kind, value):
                self.wfile.write(
                    (f"event: {kind}\ndata: " + json.dumps(value) + "\n\n").encode()
                )

            if self.path.endswith("/responses"):
                part = {"type": "output_text", "text": "ROUTED", "annotations": []}
                item = {
                    "id": "msg_fixture",
                    "type": "message",
                    "role": "assistant",
                    "status": "completed",
                    "content": [part],
                }
                response = {
                    "id": "resp_fixture",
                    "object": "response",
                    "created_at": 1,
                    "status": "completed",
                    "model": body["model"],
                    "output": [item],
                    "usage": {"input_tokens": 5, "output_tokens": 3, "total_tokens": 8},
                }
                event(
                    "response.created",
                    {
                        "type": "response.created",
                        "response": {**response, "status": "in_progress", "output": []},
                    },
                )
                event(
                    "response.output_item.added",
                    {
                        "type": "response.output_item.added",
                        "output_index": 0,
                        "item": {**item, "status": "in_progress", "content": []},
                    },
                )
                event(
                    "response.content_part.added",
                    {
                        "type": "response.content_part.added",
                        "item_id": item["id"],
                        "output_index": 0,
                        "content_index": 0,
                        "part": {**part, "text": ""},
                    },
                )
                event(
                    "response.output_text.delta",
                    {
                        "type": "response.output_text.delta",
                        "item_id": item["id"],
                        "output_index": 0,
                        "content_index": 0,
                        "delta": "ROUTED",
                    },
                )
                event(
                    "response.output_item.done",
                    {
                        "type": "response.output_item.done",
                        "output_index": 0,
                        "item": item,
                    },
                )
                event(
                    "response.completed",
                    {"type": "response.completed", "response": response},
                )
            else:
                chunk = {
                    "id": "chatcmpl_fixture",
                    "object": "chat.completion.chunk",
                    "created": 1,
                    "model": body["model"],
                    "choices": [
                        {
                            "index": 0,
                            "delta": {"role": "assistant", "content": "ROUTED"},
                            "finish_reason": "stop",
                        }
                    ],
                    "usage": {
                        "prompt_tokens": 5,
                        "completion_tokens": 3,
                        "total_tokens": 8,
                    },
                }
                self.wfile.write(
                    ("data: " + json.dumps(chunk) + "\n\ndata: [DONE]\n\n").encode()
                )

    upstream = ThreadingHTTPServer(("127.0.0.1", 0), Upstream)
    threading.Thread(target=upstream.serve_forever, daemon=True).start()

    def port():
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            return sock.getsockname()[1]

    def start(name, command, extra=None):
        log = (root / f"{name}.log").open("w")
        logs.append(log)
        process = subprocess.Popen(
            command, env=env | (extra or {}), cwd=root, stdout=log, stderr=log
        )
        processes.append(process)
        return process

    def request(base, path, payload=None, headers=None):
        req = urllib.request.Request(
            base + path,
            headers={"Content-Type": "application/json", **(headers or {})},
            data=None if payload is None else json.dumps(payload).encode(),
        )
        with urllib.request.urlopen(req, timeout=10) as response:
            return json.load(response)

    def ready(process, base, path, headers=None):
        for _ in range(300):
            if process.poll() is not None:
                for log_path in root.glob("*.log"):
                    print(log_path.name, log_path.read_text()[-5000:])
                raise AssertionError(f"Temporary process exited; logs: {root}")
            try:
                return request(base, path, headers=headers)
            except (OSError, urllib.error.URLError):
                time.sleep(0.1)
        raise AssertionError(f"Readiness timeout; logs: {root}")

    env = {
        k: v
        for k, v in os.environ.items()
        if not k.startswith(("OPENCODE_", "HEADROOM_", "LLM_PLATFORM_"))
    }
    for key in (
        "HOME",
        "XDG_CONFIG_HOME",
        "XDG_CACHE_HOME",
        "XDG_DATA_HOME",
        "XDG_STATE_HOME",
        "XDG_RUNTIME_DIR",
    ):
        directory = root / key.lower()
        directory.mkdir()
        env[key] = str(directory)
    env.update(
        HEADROOM_OFFLINE="1",
        HEADROOM_TELEMETRY="off",
        HF_HUB_OFFLINE="1",
        TRANSFORMERS_OFFLINE="1",
        NO_PROXY="127.0.0.1,localhost",
    )
    origin = f"http://127.0.0.1:{upstream.server_port}"
    proxy_url = f"http://127.0.0.1:{port()}"
    opencode_url = f"http://127.0.0.1:{port()}"
    try:
        proxy = start(
            "headroom",
            [
                args.headroom,
                "proxy",
                "--port",
                proxy_url.rsplit(":", 1)[1],
                "--stateless",
                "--no-cache",
                "--no-rate-limit",
                "--no-subscription-tracking",
                "--openai-api-url",
                origin,
            ],
            {"HEADROOM_ALLOWED_BASE_URLS": origin},
        )
        ready(proxy, proxy_url, "/health")
        config_dir = Path(env["XDG_CONFIG_HOME"]) / "opencode"
        config_dir.mkdir()
        seed = root / "catalog"
        seed.mkdir()
        (seed / "package.json").write_text(
            json.dumps(
                {
                    "name": "fixture-catalog",
                    "type": "module",
                    "exports": {".": "./index.mjs"},
                }
            )
        )
        (seed / "index.mjs").write_text(
            '''export default { id: "fixture.llm-platform", async setup(ctx) {
          const registration = await ctx.catalog.transform(catalog => {
            catalog.provider.update("llmplatform", p => Object.assign(p, {
              name: "Fixture", activation: "enabled", package: "@opencode/ai/providers/openai-compatible",
              settings: { baseURL: "'''
            + origin
            + """/v1/openai", apiKey: "fixture-project" }
            }));
            for (const [id, pkg] of [["chat", undefined], ["responses", "@opencode/ai/providers/openai/responses"]]) {
              catalog.model.update("llmplatform", id, m => Object.assign(m, { package: pkg }));
            }
          });
          return () => registration.dispose();
        }};"""
        )
        plugins = [{"package": seed.as_uri()}]
        if args.catalog_plugin:
            plugins = [
                {
                    "package": Path(args.catalog_plugin).as_uri(),
                    "options": {
                        "baseURL": origin + "/v1/openai",
                        "projectId": "fixture-project",
                        "refreshIntervalMs": 0,
                    },
                }
            ]
        if Path(args.plugin).exists():
            plugins.append(
                {
                    "package": Path(args.plugin).as_uri(),
                    "options": {
                        "proxyURL": proxy_url,
                        "upstreamBaseURL": origin + "/v1/openai",
                    },
                }
            )
        config = {
            "plugins": plugins,
            "providers": {
                "llmplatform": {
                    "settings": {"baseURL": proxy_url + "/v1"},
                    "headers": {"x-headroom-base-url": origin},
                    "websocket": False,
                }
            },
        }
        config_path = config_dir / "opencode.json"
        config_path.write_text(json.dumps(config))
        password = secrets.token_hex(24)
        auth = "Basic " + base64.b64encode(("opencode:" + password).encode()).decode()
        headers = {"Authorization": auth, "x-opencode-directory": str(config_dir)}
        oc = start(
            "opencode",
            [
                args.opencode,
                "serve",
                "--hostname",
                "127.0.0.1",
                "--port",
                opencode_url.rsplit(":", 1)[1],
            ],
            {
                "OPENCODE_CONFIG": str(config_path),
                "OPENCODE_DB": ":memory:",
                "OPENCODE_SERVER_USERNAME": "opencode",
                "OPENCODE_SERVER_PASSWORD": password,
            },
        )
        ready(oc, opencode_url, "/api/health", headers)
        for _ in range(80):
            models = request(opencode_url, "/api/model", headers=headers)["data"]
            selected = [m for m in models if m["providerID"] == "llmplatform"]
            if len(selected) == 2:
                break
            time.sleep(0.1)
        else:
            print(json.dumps(request(opencode_url, "/api/plugin", headers=headers)))
            raise AssertionError(f"Model discovery failed; logs: {root}")
        for model in selected:
            expected = "/v1/openai/" + (
                "responses" if model["id"] == "responses" else "chat/completions"
            )
            assert (
                model.get("headers", {}).get("x-headroom-original-path") == expected
            ), f"Native v2 routing missing for {model['id']}"
            assert model["settings"]["baseURL"] == proxy_url + "/v1"
            assert model.get("websocket") is False
            result = request(
                opencode_url,
                "/api/generate",
                {
                    "model": {"providerID": "llmplatform", "id": model["id"]},
                    "prompt": "Reply ROUTED.",
                },
                headers,
            )
            assert "ROUTED" in json.dumps(result)
        assert sorted(p for p, _, _ in calls) == [
            "/v1/openai/chat/completions",
            "/v1/openai/responses",
        ], calls
        for _, sent_headers, _ in calls:
            normalized = {k.lower(): v for k, v in sent_headers.items()}
            credential = (
                "project/fixture-project" if args.catalog_plugin else "fixture-project"
            )
            assert normalized.get("authorization") == "Bearer " + credential
            assert not any(k.startswith("x-headroom-") for k in normalized)
        # A missing proxy must produce an error, never a direct upstream call.
        proxy.terminate()
        proxy.wait(timeout=10)
        try:
            request(
                opencode_url,
                "/api/generate",
                {
                    "model": {"providerID": "llmplatform", "id": "chat"},
                    "prompt": "Reply ROUTED.",
                },
                headers,
            )
            raise AssertionError(
                "Inference unexpectedly succeeded with the proxy stopped"
            )
        except (urllib.error.URLError, TimeoutError):
            pass
        assert len(calls) == 2, "Inference bypassed the stopped proxy"
        print(
            f"PASS: native Chat/Responses routing, authentication, and no direct fallback; logs: {root}"
        )
    finally:
        for process in reversed(processes):
            if process.poll() is None:
                process.terminate()
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    process.kill()
                    process.wait()
        upstream.shutdown()
        for log in logs:
            log.close()


if __name__ == "__main__":
    main()
