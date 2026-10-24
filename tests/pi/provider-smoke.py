#!/usr/bin/env python3
"""Load the immutable provider package in real Pi, without WARP or inference."""
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = sys.argv[1]
package = json.loads(Path(sys.argv[2]).read_text())["runtimePath"]
with tempfile.TemporaryDirectory(prefix="pi-provider-smoke-", dir=os.environ.get("TMPDIR", "/tmp/opencode")) as directory:
    root = Path(directory)
    env = {key: os.environ[key] for key in ["PATH", "LANG", "LC_ALL"] if key in os.environ}
    env.update(HOME=str(root), XDG_CONFIG_HOME=str(root / ".config"), PI_CODING_AGENT_DIR=str(root / "agent"),
               PI_OFFLINE="1", PI_TELEMETRY="0", LLM_PLATFORM_PROJECT_ID="fixture-project")
    args = [binary, "--offline", "--no-extensions", "-e", package + "/extensions/llm-platform.ts", "--no-mcp",
            "--no-skills", "--no-context-files", "--no-themes", "--no-prompt-templates", "--no-session",
            "--model", "llm-platform/claude-sonnet-5-5", "-p", "/reddit status"]
    for proxy in [False, True]:
        scoped = dict(env)
        if proxy:
            scoped.update(LLM_PLATFORM_INFERENCE_PROXY_URL="http://127.0.0.1:19878", LLM_PLATFORM_INFERENCE_PROXY_REQUIRED="1")
        result = subprocess.run(args, env=scoped, cwd=root, text=True, capture_output=True, timeout=30)
        output = result.stdout + result.stderr
        assert result.returncode == 0, output
        assert "Project: fixture-project" in output and "Models:" in output, output
    result = subprocess.run(args, env=dict(env, LLM_PLATFORM_INFERENCE_PROXY_REQUIRED="1"), cwd=root,
                            text=True, capture_output=True, timeout=30)
    assert result.returncode != 0, result.stdout + result.stderr
    assert "inference proxy is required" in result.stdout + result.stderr
print("PASS: packaged production entry loads /reddit without inference; missing required proxy prevents loading")
