import { appendFileSync } from "node:fs";
export default function (pi) {
  const record = value => appendFileSync(process.env.PI_UI_EVENTS, JSON.stringify(value) + "\n");
  pi.registerProvider("fixture", { baseUrl: process.env.PI_UI_BASE_URL, apiKey: "synthetic-only", api: "openai-completions",
    models: [{ id: "unit", name: "unit", reasoning: true, input: ["text"], contextWindow: 100000, maxTokens: 1024,
      cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }] });
  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setStatus("fixture", "PRESERVED_STATUS");
    ctx.ui.setStatus("managed-routing", "build");
    record({ startup: true, theme: ctx.ui.theme.name, nativeTools: pi.getAllTools().filter(tool => ["read", "edit"].includes(tool.name)).map(tool => ({ name: tool.name, source: tool.sourceInfo })) });
  });
  pi.on("ui_prompt_start", event => record({ event: "start", kind: event.kind }));
  pi.on("ui_prompt_end", event => record({ event: "end", kind: event.kind }));
  pi.on("tool_result", event => record({ tool: event.toolName, details: event.details }));
  pi.on("agent_settled", () => record({ settled: true }));
  pi.registerCommand("capture", { description: "Synthetic input witness", handler: async args => record({ capture: args }) });
  pi.registerCommand("set-thinking", { description: "Native thinking-level witness", handler: async level => pi.setThinkingLevel(level) });
  pi.registerCommand("dialog", { description: "Native question witness", handler: async (_args, ctx) => {
    const answer = await ctx.ui.select("NATIVE_QUESTION", ["Yes fixture", "No fixture"]);
    record({ answer: answer ?? null });
  } });
}
