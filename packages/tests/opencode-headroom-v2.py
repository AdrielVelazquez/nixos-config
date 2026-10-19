"""Exercise the published provider and local routing plugin with real binaries."""

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
    parser.add_argument("--catalog-plugin", required=True)
    parser.add_argument("--superpowers", required=True)
    parser.add_argument("--learning-skills", required=True)
    args = parser.parse_args()
    root = Path(tempfile.mkdtemp(prefix="opencode-headroom-v2-"))
    calls = []
    history_calls = []
    history_errors = []
    signature_sentinel = "skip_thought_signature_validator"
    unsigned_signature = "c2tpcF90aG91Z2h0X3NpZ25hdHVyZV92YWxpZGF0b3I="
    real_signature = "cmVhbC1nZW1pbmktc2lnbmF0dXJl"
    processes = []
    logs = []
    catalog = [
        ("chat", "chat_completions"),
        ("responses", "responses"),
        ("gemini-3-test", "generate_content"),
    ]
    expected_routes = {
        "chat": "/v1/openai/chat/completions",
        "responses": "/v1/openai/responses",
        "refreshed": "/v1/openai/responses",
        "gemini-3-test": "/v1/gemini/models/gemini-3-test:streamGenerateContent?alt=sse",
        "refreshed-gemini": "/v1/gemini/models/refreshed-gemini:streamGenerateContent?alt=sse",
    }

    class Upstream(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def do_GET(self):
            if self.path.split("?", 1)[0] != "/v1/openai/models":
                self.send_error(404)
                return
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
                for name, api in catalog
            ]
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({"object": "list", "data": data}).encode())

        def do_POST(self):
            body = json.loads(self.rfile.read(int(self.headers["Content-Length"])))
            calls.append((self.path, dict(self.headers), body))
            history = bool(body.get("tools"))
            if history:
                history_calls.append(self.path)
            if self.path not in expected_routes.values():
                self.send_error(404)
                return
            self.send_response(200)
            self.send_header("Content-Type", "text/event-stream")
            self.end_headers()

            def event(kind, value):
                self.wfile.write(
                    (f"event: {kind}\ndata: " + json.dumps(value) + "\n\n").encode()
                )

            if self.path.startswith("/v1/gemini/models/"):
                parts = [{"text": "ROUTED"}]
                if history:
                    sent_parts = [
                        part
                        for content in body["contents"]
                        for part in content["parts"]
                    ]
                    signatures = [
                        part.get("thoughtSignature")
                        for part in sent_parts
                        if "functionCall" in part
                    ]
                    native_turn = sum(
                        path.startswith("/v1/gemini/") for path in history_calls
                    )
                    if (
                        unsigned_signature not in signatures
                        or any(
                            signature not in (unsigned_signature, real_signature)
                            for signature in signatures
                        )
                        or (native_turn == 2 and real_signature not in signatures)
                        or not any(
                            signature_sentinel in part.get("text", "")
                            for part in sent_parts
                        )
                    ):
                        history_errors.append({"signatures": signatures})
                    elif native_turn == 1:
                        parts = [
                            {
                                "functionCall": {
                                    "name": "read",
                                    "args": {"path": str(history_path)},
                                },
                                "thoughtSignature": real_signature,
                            }
                        ]
                else:
                    assert body["contents"][0]["parts"][0]["text"] == "Reply ROUTED.", body
                chunk = {
                    "candidates": [
                        {
                            "index": 0,
                            "content": {"role": "model", "parts": parts},
                            "finishReason": "STOP",
                        }
                    ],
                    "usageMetadata": {
                        "promptTokenCount": 5,
                        "candidatesTokenCount": 3,
                        "totalTokenCount": 8,
                    },
                }
                self.wfile.write(("data: " + json.dumps(chunk) + "\n\n").encode())
            elif self.path.endswith("/responses"):
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
                if history and not any(
                    message["role"] == "tool" for message in body["messages"]
                ):
                    chunk["choices"][0].update(
                        delta={
                            "role": "assistant",
                            "tool_calls": [
                                {
                                    "index": 0,
                                    "id": "call_history",
                                    "type": "function",
                                    "function": {
                                        "name": "read",
                                        "arguments": json.dumps(
                                            {"path": str(history_path)}
                                        ),
                                    },
                                }
                            ],
                        },
                        finish_reason="tool_calls",
                    )
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

    def request(base, path, payload=None, headers=None, timeout=10):
        req = urllib.request.Request(
            base + path,
            headers={"Content-Type": "application/json", **(headers or {})},
            data=None if payload is None else json.dumps(payload).encode(),
        )
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return None if response.status == 204 else json.load(response)

    def ready(process, base, path, headers=None):
        last_error = None
        for _ in range(300):
            if process.poll() is not None:
                for log_path in root.glob("*.log"):
                    print(log_path.name, log_path.read_text()[-5000:])
                raise AssertionError(f"Temporary process exited; logs: {root}")
            try:
                return request(base, path, headers=headers)
            except (OSError, urllib.error.URLError) as error:
                last_error = error
                time.sleep(0.1)
        for log_path in root.glob("*.log"):
            print(log_path.name, log_path.read_text()[-5000:])
        raise AssertionError(f"Readiness timeout: {last_error!r}; logs: {root}")

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
        OPENCODE_DISABLE_MODELS_FETCH="true",
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
        history_path = config_dir / "tool-history.txt"
        history_path.write_text(signature_sentinel)
        (config_dir / "skills").symlink_to(args.learning_skills, target_is_directory=True)
        plugins = [
            {
                "package": Path(args.catalog_plugin).resolve().as_uri(),
                "options": {
                    "baseURL": origin + "/v1/openai",
                    "projectId": "fixture-project",
                    "refreshIntervalMs": 100,
                },
            }
        ]
        if Path(args.plugin).exists():
            plugins.append(
                {
                    "package": Path(args.plugin).resolve().as_uri(),
                    "options": {
                        "proxyURL": proxy_url,
                        "upstreamBaseURL": origin + "/v1/openai",
                    },
                }
            )
        config = {
            "plugins": plugins + [{"package": Path(args.superpowers).resolve().as_uri()}],
            "enabled_providers": ["llmplatform"],
            "providers": {
                "llmplatform": {
                    "settings": {"baseURL": proxy_url + "/v1"},
                    "headers": {"x-headroom-base-url": origin},
                    "transport": "http",
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
        ready(oc, opencode_url, "/api/info", headers)
        for _ in range(80):
            models = request(opencode_url, "/api/model", headers=headers)["data"]
            selected = [m for m in models if m["providerID"] == "llmplatform"]
            if len(selected) == 3:
                break
            time.sleep(0.1)
        else:
            print(json.dumps(request(opencode_url, "/api/plugin", headers=headers)))
            raise AssertionError(f"Model discovery failed; logs: {root}")
        skills = request(opencode_url, "/api/skill", headers=headers)["data"]
        discovered_skills = {skill["name"]: skill for skill in skills}
        skill_paths = sorted((Path(args.superpowers) / "skills").glob("*/SKILL.md"))
        assert skill_paths, "The pinned Superpowers source must contain skills"
        learning_paths = sorted(Path(args.learning_skills).glob("*/SKILL.md"))
        assert {path.parent.name for path in learning_paths} == {
            "ce-compound",
            "ce-compound-refresh",
        }
        for name, reference in (
            ("ce-compound", "research.md"),
            ("ce-compound-refresh", "modes.md"),
        ):
            assert (Path(args.learning_skills) / name / "references" / reference).is_file()
        skill_paths += learning_paths
        for skill_path in skill_paths:
            name = skill_path.parent.name
            assert name in discovered_skills, f"Native skill not discovered: {name}"
            assert discovered_skills[name]["content"]
            assert Path(discovered_skills[name]["path"]).resolve() == skill_path.resolve()
        # OpenCode also registers its own help/report skills under /builtin.
        installed_skills = {
            name
            for name, skill in discovered_skills.items()
            if not Path(skill["path"]).is_relative_to("/builtin")
        }
        assert installed_skills == {path.parent.name for path in skill_paths}, (
            "Unexpected workflow skills were loaded",
            sorted(installed_skills),
        )

        def generate(model):
            if model["id"] in ("gemini-3-test", "refreshed-gemini"):
                # A native model must not be rewritten onto the OpenAI Chat route.
                assert model["package"] == "@opencode/ai/providers/google", model
                assert model["settings"]["baseURL"] == proxy_url + "/v1/gemini", model
                assert "x-headroom-original-path" not in model.get("headers", {}), model
            else:
                assert (
                    model.get("headers", {}).get("x-headroom-original-path")
                    == expected_routes[model["id"]]
                ), f"Native v2 routing missing for {model['id']}"
                assert model["settings"]["baseURL"] == proxy_url + "/v1"
            result = request(
                opencode_url,
                "/api/experimental/generate",
                {
                    "model": {"providerID": "llmplatform", "id": model["id"]},
                    "prompt": "Reply ROUTED.",
                },
                headers,
            )
            assert "ROUTED" in json.dumps(result)

        for model in selected:
            generate(model)

        # A provider refresh must replay routing onto newly discovered models.
        catalog.extend(
            [("refreshed", "responses"), ("refreshed-gemini", "generate_content")]
        )
        for _ in range(80):
            models = request(opencode_url, "/api/model", headers=headers)["data"]
            refreshed = [
                model
                for model in models
                if model["providerID"] == "llmplatform"
                and model["id"] in ("refreshed", "refreshed-gemini")
            ]
            if len(refreshed) == 2:
                break
            time.sleep(0.1)
        else:
            raise AssertionError(f"Provider refresh failed; logs: {root}")
        for model in refreshed:
            generate(model)
        assert sorted(p for p, _, _ in calls) == [
            "/v1/gemini/models/gemini-3-test:streamGenerateContent?alt=sse",
            "/v1/gemini/models/refreshed-gemini:streamGenerateContent?alt=sse",
            "/v1/openai/chat/completions",
            "/v1/openai/responses",
            "/v1/openai/responses",
        ], calls

        # Switching a tool-using conversation to Gemini needs the provider's
        # unsigned-history rewrite even though the request now uses loopback.
        session = request(
            opencode_url,
            "/api/session",
            {
                "title": "Gemini tool-history regression",
                "location": {"directory": str(config_dir)},
                "model": {"providerID": "llmplatform", "id": "chat"},
            },
            headers,
        )["data"]["id"]
        request(
            opencode_url,
            f"/api/session/{session}/prompt",
            {"text": "Seed tool history: " + signature_sentinel},
            headers,
        )
        request(
            opencode_url,
            f"/api/experimental/session/{session}/wait",
            {},
            headers,
            timeout=30,
        )
        context = request(opencode_url, f"/api/session/{session}/context", headers=headers)[
            "data"
        ]
        assert any(
            part.get("type") == "tool" and part["state"]["status"] == "completed"
            for message in context
            if message["type"] == "assistant"
            for part in message["content"]
        ), context
        request(
            opencode_url,
            f"/api/session/{session}/model",
            {"model": {"providerID": "llmplatform", "id": "gemini-3-test"}},
            headers,
        )
        request(
            opencode_url,
            f"/api/session/{session}/prompt",
            {"text": "Continue with Gemini: " + signature_sentinel},
            headers,
        )
        request(
            opencode_url,
            f"/api/experimental/session/{session}/wait",
            {},
            headers,
            timeout=30,
        )
        assert not history_errors, history_errors
        assert history_calls == [
            "/v1/openai/chat/completions",
            "/v1/openai/chat/completions",
            "/v1/gemini/models/gemini-3-test:streamGenerateContent?alt=sse",
            "/v1/gemini/models/gemini-3-test:streamGenerateContent?alt=sse",
        ], history_calls
        context = request(opencode_url, f"/api/session/{session}/context", headers=headers)[
            "data"
        ]
        native_messages = [
            message
            for message in context
            if message["type"] == "assistant" and message["model"]["id"] == "gemini-3-test"
        ]
        assert native_messages and not any(
            message.get("error") for message in native_messages
        ), context
        assert any(
            part.get("text") == "ROUTED" for part in native_messages[-1]["content"]
        ), native_messages
        for _, sent_headers, _ in calls:
            normalized = {k.lower(): v for k, v in sent_headers.items()}
            assert normalized.get("authorization") == "Bearer project/fixture-project"
            assert not any(k.startswith("x-headroom-") for k in normalized)
        # A missing proxy must produce an error, never a direct upstream call.
        proxy.terminate()
        proxy.wait(timeout=10)
        for model in selected:
            try:
                request(
                    opencode_url,
                    "/api/experimental/generate",
                    {
                        "model": {"providerID": "llmplatform", "id": model["id"]},
                        "prompt": "Reply ROUTED.",
                    },
                    headers,
                )
                raise AssertionError(
                    f"{model['id']} inference succeeded with the proxy stopped"
                )
            except (urllib.error.URLError, TimeoutError):
                pass
        assert len(calls) == 9, "Inference bypassed the stopped proxy"
        print(
            f"PASS: published provider, Chat/Responses/Gemini routing, "
            f"tool-history signatures, refresh, skills, authentication, "
            f"and no direct fallback; logs: {root}"
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
