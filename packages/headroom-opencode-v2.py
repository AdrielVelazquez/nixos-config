"""Translate Headroom's generated v1 settings before launching OpenCode v2."""

import json
import os
import sys
from pathlib import Path


def merge(base, override):
    result = dict(base)
    for key, value in override.items():
        result[key] = (
            merge(result[key], value)
            if isinstance(result.get(key), dict) and isinstance(value, dict)
            else value
        )
    return result


def native_config(config):
    providers = config.setdefault("providers", {})
    for name, provider in config.pop("provider", {}).items():
        provider = dict(provider)
        npm = provider.pop("npm", None)
        if npm:
            provider["package"] = {
                "@ai-sdk/openai-compatible": "@opencode/ai/providers/openai-compatible",
                "@ai-sdk/openai": "@opencode/ai/providers/openai",
                "@ai-sdk/anthropic": "@opencode/ai/providers/anthropic",
            }.get(npm, "aisdk:" + npm)
        options = provider.pop("options", {})
        headers = options.pop("headers", {})
        if options:
            provider["settings"] = merge(options, provider.get("settings", {}))
        if headers:
            provider["headers"] = merge(headers, provider.get("headers", {}))
        providers[name] = merge(provider, providers.get(name, {}))

    mcp = config.get("mcp", {})
    for name, server in list(mcp.items()):
        if (
            name in ("servers", "timeout")
            or not isinstance(server, dict)
            or "type" not in server
        ):
            continue
        server = dict(mcp.pop(name))
        if "enabled" in server:
            server["disabled"] = not server.pop("enabled")
        if isinstance(server.get("timeout"), (int, float)):
            server["timeout"] = {
                "startup": server["timeout"],
                "catalog": server["timeout"],
            }
        servers = mcp.setdefault("servers", {})
        servers[name] = merge(servers.get(name, {}), server)
    return config


def main():
    config_path = Path(os.environ["OPENCODE_CONFIG"])
    config = native_config(json.loads(config_path.read_text()))
    inline = native_config(json.loads(os.environ["OPENCODE_CONFIG_CONTENT"]))
    proxy_url = inline["providers"]["headroom"]["settings"]["baseURL"].removesuffix(
        "/v1"
    )
    no_serena = os.environ.pop("HEADROOM_OPENCODE_NO_SERENA", "0") == "1"
    for document in (config, inline):
        if "llmplatform" in config["providers"]:
            document["providers"].setdefault("llmplatform", {}).setdefault(
                "settings", {}
            )["baseURL"] = proxy_url + "/v1"
        server = document.get("mcp", {}).get("servers", {}).get("headroom")
        if server is not None:
            server.setdefault("environment", {})["HEADROOM_PROXY_URL"] = proxy_url
        serena = document.get("mcp", {}).get("servers", {}).get("serena")
        if no_serena and serena is not None:
            serena["disabled"] = True
    config_path.write_text(json.dumps(config))
    os.environ["OPENCODE_CONFIG_CONTENT"] = json.dumps(inline)
    os.environ["HEADROOM_PROXY_URL"] = proxy_url
    launcher_dir = os.environ.pop("HEADROOM_OPENCODE_LAUNCHER_DIR", "")
    os.environ["PATH"] = os.pathsep.join(
        entry for entry in os.environ["PATH"].split(os.pathsep) if entry != launcher_dir
    )
    args = sys.argv[2:]
    # A pre-existing v2 server cannot inherit a wrapped session's configuration.
    if not args or args[0].startswith("-") or Path(args[0]).is_dir():
        args = ["--standalone", *args]
    elif args[0] in ("run", "mini"):
        args = [args[0], "--standalone", *args[1:]]
    os.execv(sys.argv[1], [sys.argv[1], *args])


if __name__ == "__main__":
    main()
