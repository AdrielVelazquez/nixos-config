import { readFileSync, renameSync, writeFileSync } from "node:fs";

function record(value) {
  let previous = {};
  try { previous = JSON.parse(readFileSync(process.env.OMP_MCP_STATE, "utf8")); } catch {}
  const temporary = process.env.OMP_MCP_STATE + "." + process.pid + ".tmp";
  writeFileSync(temporary, JSON.stringify({ ...previous, ...value, revision: (previous.revision ?? 0) + 1 }));
  renameSync(temporary, process.env.OMP_MCP_STATE);
}

export default function (pi) {
  pi.registerProvider("fixture", {
    apiKey: "synthetic-only", api: "openai-completions", baseUrl: process.env.OMP_MCP_GATEWAY + "/v1",
    models: [{ id: "unit", name: "unit", reasoning: false, input: ["text"], contextWindow: 100000,
      maxTokens: 1024, cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }],
  });
  pi.on("session_start", async (_event, ctx) => {
    if (ctx.agent.kind !== "main") {
      try { await pi.unregisterMcpServer("reddit-tools"); record({ childMutationAccepted: true }); }
      catch (error) {
        const state = JSON.parse(readFileSync(process.env.OMP_MCP_STATE, "utf8"));
        record({ childMutationRefusals: (state.childMutationRefusals ?? 0) + (/main-session only/.test(error.message) ? 1 : 0) });
      }
      return;
    }
    try {
      const config: any = { type: "http", url: process.env.OMP_MCP_GATEWAY + "/mcp" };
      if (process.env.OMP_MCP_AUTH_MODE) {
        config.oauth = { scope: "openid offline_access tool:search:read",
          expectedIssuer: process.env.OMP_MCP_GATEWAY + "/oauth", expectedResource: process.env.OMP_MCP_GATEWAY + "/mcp" };
        config.auth = { type: "oauth", credentialId: "mcp_oauth:legacy-synthetic-binding" };
      }
      await pi.registerMcpServer("reddit-tools", config, async call => {
        record({ policyCwd: call.cwd });
        return call.toolName === "search__denied" ? { allow: false, reason: "OMP_NATIVE_POLICY_DENIED" } : { allow: true };
      });
      record({ servers: pi.getMcpServers() });
    } catch (error) { record({ error: String(error.message) }); }
  });
  pi.registerCommand("native-mcp-state", { description: "Synthetic native MCP state witness", handler: async (_args, ctx) => {
    record({ servers: pi.getMcpServers(), nativeTools: pi.getAllTools().map(tool => tool.name) });
    ctx.ui.notify("NATIVE_MCP_STATE_RECORDED", "info");
  } });
  pi.registerCommand("native-mcp-remove", { description: "Synthetic owned removal witness", handler: async (_args, ctx) => {
    if (ctx.agent.kind !== "main") return;
    try {
      await pi.unregisterMcpServer("reddit-tools");
      record({ removed: !pi.getMcpServers().some(server => server.name === "reddit-tools") });
    } catch (error) { record({ removalError: String(error.message) }); }
  } });
}
