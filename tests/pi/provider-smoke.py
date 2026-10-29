#!/usr/bin/env python3
"""Load the packaged production provider and inspect routing without live inference."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary = sys.argv[1]
fixture = json.loads(Path(sys.argv[2]).read_text())
with tempfile.TemporaryDirectory(
    prefix="pi-provider-smoke-", dir=os.environ.get("TMPDIR", "/tmp/opencode")
) as directory:
    root = Path(directory)
    env = {
        key: os.environ[key] for key in ["PATH", "LANG", "LC_ALL"] if key in os.environ
    }
    env.update(
        HOME=str(root),
        XDG_CONFIG_HOME=str(root / ".config"),
        PI_CODING_AGENT_DIR=str(root / "agent"),
        PI_OFFLINE="1",
        PI_TELEMETRY="0",
        LLM_PLATFORM_PROJECT_ID="fixture-project",
    )
    probe = root / "probe.ts"
    probe.write_text("""export default pi => pi.on('session_start', (_event, ctx) => {
  console.log('ROUTING_BASES=' + JSON.stringify([...new Set(
    ctx.modelRegistry.getModelsOfType('chat', 'llm-platform').map(model => model.baseUrl)
  )]));
});
""")
    proxy = "http://127.0.0.1:19878"
    owned = {
        "HEADROOM_PROXY_URL": proxy,
        "LLM_PLATFORM_INFERENCE_PROXY_URL": proxy,
        "LLM_PLATFORM_INFERENCE_PROXY_REQUIRED": "1",
    }
    cases = [
        ("owned", owned, True),
        ("missing", {"HEADROOM_PROXY_URL": proxy}, False),
        (
            "foreign",
            {**owned, "LLM_PLATFORM_INFERENCE_PROXY_URL": "http://127.0.0.1:19879"},
            False,
        ),
        (
            "not-required",
            {**owned, "LLM_PLATFORM_INFERENCE_PROXY_REQUIRED": "0"},
            False,
        ),
        (
            "remote",
            {
                **owned,
                "HEADROOM_PROXY_URL": "http://10.0.0.5:8787",
                "LLM_PLATFORM_INFERENCE_PROXY_URL": "http://10.0.0.5:8787",
            },
            False,
        ),
    ]
    for required, key in [(False, "directRuntimePath"), (True, "runtimePath")]:
        package = fixture[key]
        args = [
            binary,
            "--offline",
            "--no-extensions",
            "-e",
            package + "/extensions/llm-platform.ts",
            "-e",
            str(probe),
            "--no-mcp",
            "--no-skills",
            "--no-context-files",
            "--no-themes",
            "--no-prompt-templates",
            "--no-session",
            "--model",
            "llm-platform/claude-sonnet-5-5",
            "-p",
            "/reddit status",
        ]
        for name, inherited, valid in cases:
            result = subprocess.run(
                args,
                env={**env, **inherited},
                cwd=root,
                text=True,
                capture_output=True,
                timeout=30,
            )
            output = result.stdout + result.stderr
            if required and not valid:
                assert result.returncode != 0, (name, output)
                assert "managed Headroom launcher" in output, (name, output)
                continue
            assert result.returncode == 0, (required, name, output)
            assert "Project: fixture-project" in output and "Models:" in output, output
            bases = next(
                line.removeprefix("ROUTING_BASES=")
                for line in output.splitlines()
                if line.startswith("ROUTING_BASES=")
            )
            expected = (
                proxy + "/v1"
                if required
                else "https://llm-platform.snooguts.net/v1/openai"
            )
            assert json.loads(bases) == [expected], (required, name, bases)
print(
    "PASS: production LLM provider enforces owned routing; disabled routing ignores inherited proxy contracts; no live inference"
)
