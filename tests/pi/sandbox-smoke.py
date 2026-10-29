import argparse
import json
import os
import shlex
import signal
import subprocess
import tempfile
from pathlib import Path

FIXTURE = r"""
import assert from "node:assert/strict";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";

export default function(pi: any) {
  let calls = 0;
  const server = createServer((_request, response) => {
    calls++;
    const delta = calls === 1
      ? {role: "assistant", tool_calls: [{index: 0, id: "sandbox-probe", type: "function", function: {name: "sandbox_probe", arguments: "{}"}}]}
      : {role: "assistant", content: "probe complete"};
    const chunk = (body: any) => ({id: "synthetic", object: "chat.completion.chunk", created: 1, model: "probe", choices: [{index: 0, ...body}]});
    response.writeHead(200, {"Content-Type": "text/event-stream"});
    response.write("data: " + JSON.stringify(chunk({delta, finish_reason: null})) + "\n\n");
    response.write("data: " + JSON.stringify(chunk({delta: {}, finish_reason: calls === 1 ? "tool_calls" : "stop"})) + "\n\n");
    response.end("data: [DONE]\n\n");
  });
  pi.registerProvider("sandbox-fixture", {
    baseUrl: "http://127.0.0.1:18765/v1", apiKey: "synthetic-only", api: "openai-completions",
    models: [{id: "probe", name: "Probe", reasoning: false, input: ["text"], contextWindow: 200000, maxTokens: 2048,
      cost: {input: 0, output: 0, cacheRead: 0, cacheWrite: 0}}],
  });
  pi.on("session_start", async () => {
    await new Promise<void>((resolve, reject) => { server.once("error", reject); server.listen(18765, "127.0.0.1", resolve); });
  });
  pi.on("session_shutdown", () => { server.closeAllConnections(); server.close(); });
  pi.registerTool({
    name: "sandbox_probe", label: "Sandbox probe", description: "Run the synthetic microVM isolation checks",
    parameters: {type: "object", properties: {}},
    async execute(_id: string, _params: unknown, _signal: unknown, _update: unknown, ctx: any) {
      assert(readFileSync("/etc/os-release", "utf8").includes("ID=pi-sandbox"));
      assert(!existsSync(__CANARY__));
      assert(!process.env.SSH_AUTH_SOCK);
      assert(!process.env.ANTHROPIC_API_KEY);
      assert(!process.env.TUIOS_SESSION);
      assert(process.env.SANDBOX_TEST_TOKEN?.startsWith("$MSB_"), "The guest must receive only a credential placeholder");
      assert(existsSync("/usr/bin/env"), "Guest project shebangs require /usr/bin/env");
      const names = pi.getAllTools().map((tool: any) => tool.name);
      for (const name of ["eval", "job", "lsp_status", "dap_launch", "subagent", "ast_grep_run"]) assert(names.includes(name), "Missing managed tool: " + name);
      const health = await fetch(process.env.HEADROOM_PROXY_URL + "/health");
      assert(health.ok, "Guest-owned Headroom did not start");
      const evaluated = await ctx.executeTool("eval", {code: 'import os\nfrom pathlib import Path\nassert "ID=pi-sandbox" in Path("/etc/os-release").read_text()\nassert "SSH_AUTH_SOCK" not in os.environ\nprint("SANDBOX_PYTHON_OK")'});
      assert(JSON.stringify(evaluated).includes("SANDBOX_PYTHON_OK"), JSON.stringify(evaluated));
      const started = await ctx.executeTool("job", {op: "start", command: "python3 -c 'from pathlib import Path; assert \"ID=pi-sandbox\" in Path(\"/etc/os-release\").read_text(); print(\"SANDBOX_JOB_OK\")'", name: "sandbox-smoke"});
      const job = JSON.stringify(started).match(/#(\d+)/);
      assert(job, JSON.stringify(started));
      const output = await ctx.executeTool("job", {op: "output", id: Number(job[1]), wait: 30});
      assert(JSON.stringify(output).includes("SANDBOX_JOB_OK"), JSON.stringify(output));
      const report = {guest: true, hostCanaryHidden: true, hostCredentialsHidden: true, secretPlaceholder: true, managedTools: names, headroom: true, python: true, job: true};
      writeFileSync("/workspace/report.json", JSON.stringify(report));
      return {content: [{type: "text", text: "sandbox probe passed"}], details: report, terminate: true};
    },
  });
}
"""


def invoke(command, args, environment, timeout=600):
    process = subprocess.Popen(
        command + args,
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=environment,
    )
    try:
        stdout, stderr = process.communicate("", timeout=timeout)
    except subprocess.TimeoutExpired:
        process.send_signal(signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=45)
        except subprocess.TimeoutExpired:
            process.kill()
            stdout, stderr = process.communicate()
        raise RuntimeError("Guest smoke timed out: " + stderr[-6000:])
    if process.returncode:
        raise RuntimeError(
            f"Guest exited {process.returncode}: {stderr[-6000:]}\n{stdout[-6000:]}"
        )
    return stdout


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--launcher", type=Path, required=True)
    options = parser.parse_args()
    command = shlex.split(options.launcher.read_text(), comments=True)
    if command[0] != "exec" or command[-1] != "$@":
        raise RuntimeError("Unexpected generated launcher")
    command = command[1:-1]
    index = command.index("--config") + 1
    config = json.loads(Path(command[index]).read_text())
    if config["secretBindings"]:
        raise RuntimeError("Smoke testing must not use real secret bindings")
    with tempfile.TemporaryDirectory(prefix="pi-sandbox-smoke-") as temporary:
        root = Path(temporary)
        repo = root / "project"
        repo.mkdir()
        subprocess.run([config["git"], "init", "-q", str(repo)], check=True)
        canary = root / "host-only-canary"
        canary.write_text("host-only-test-data")
        (repo / "probe.ts").write_text(
            FIXTURE.replace("__CANARY__", json.dumps(str(canary)))
        )
        config["stateDir"] = str(root / "state")
        manifest = root / "manifest.json"
        manifest.write_text(json.dumps(config))
        command[index] = str(manifest)
        environment = {
            **os.environ,
            "SSH_AUTH_SOCK": "/host/ssh-agent",
            "ANTHROPIC_API_KEY": "synthetic-host-only",
            "TUIOS_SESSION": "synthetic-host-pane",
        }
        base = ["--project", str(repo), "--"]
        version = invoke(command, base + ["--version"], environment)
        print("Guest Pi version:", version.strip(), flush=True)
        token = root / "synthetic-token"
        token_value = "synthetic-only-" + os.urandom(24).hex()
        token.write_text(token_value)
        config["secretBindings"] = {
            "SANDBOX_TEST_TOKEN": {
                "sourceFile": str(token),
                "allowedHosts": ["example.com"],
            }
        }
        manifest.write_text(json.dumps(config))
        transcript = invoke(
            command,
            base
            + [
                "--mode",
                "json",
                "--no-mcp",
                "--extension",
                "/workspace/probe.ts",
                "--provider",
                "sandbox-fixture",
                "--model",
                "probe",
                "-p",
                "Run sandbox_probe once.",
            ],
            environment,
        )
        if not (repo / "report.json").exists():
            raise RuntimeError("Guest probe produced no report: " + transcript[-6000:])
        report = json.loads((repo / "report.json").read_text())
        assert canary.read_text() == "host-only-test-data"
        for path in (root / "state" / "runtime").rglob("*"):
            if path.is_file() and (
                path.suffix in {".json", ".db", ".sqlite"} or path.name.endswith("-wal")
            ):
                assert token_value.encode() not in path.read_bytes(), (
                    f"Raw synthetic token persisted in {path.name}"
                )
        report["managedToolCount"] = len(report.pop("managedTools"))
        print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
