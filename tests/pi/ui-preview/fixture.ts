// Dev-only fixture for tests/pi/ui-preview/preview.py: a scripted OpenAI-compatible provider plus
// footer statuses, so every visual surface renders without a real model or network.
import { appendFileSync } from "node:fs";
export default function (pi: any) {
  const record = (value: unknown) => appendFileSync(process.env.PI_UI_EVENTS!, JSON.stringify(value) + "\n");
  pi.registerProvider("fixture", {
    baseUrl: process.env.PI_UI_BASE_URL,
    apiKey: "synthetic-only",
    api: "openai-completions",
    models: [{
      id: "claude-sonnet-4", name: "Claude Sonnet 4", reasoning: true, input: ["text"],
      contextWindow: 200000, maxTokens: 8192,
      cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
    }],
  });
  pi.on("session_start", (_event: unknown, ctx: any) => {
    ctx.ui.setStatus("lsp", "LSP typescript ●");
    record({ startup: true, theme: ctx.ui.theme.name });
  });
  // Default-rendered tool, as MCP and most extension tools are, to see how foreign tools sit in the transcript.
  pi.registerTool({
    name: "probe",
    label: "Probe",
    description: "Preview-only tool",
    parameters: { type: "object", properties: { target: { type: "string" } }, required: ["target"] } as any,
    async execute(_id: string, params: any) {
      return { content: [{ type: "text", text: `probed ${params.target}\nstatus: ok\nlatency: 12ms` }], details: {} };
    },
  } as any);
  // A hook that rewrites a command the way rtk does: the transcript shows what the model asked for.
  pi.on("tool_call", (event: any) => {
    if (event.toolName === "bash" && typeof event.input?.command === "string" && event.input.command.startsWith("echo hook")) {
      event.input.command = event.input.command.replace("echo hook", "echo rewritten");
    }
  });
  pi.on("agent_settled", () => record({ settled: true }));
}
