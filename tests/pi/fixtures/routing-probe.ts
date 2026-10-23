import { appendFileSync, existsSync, writeFileSync } from "node:fs";
import { Type } from "typebox";

export default async function (pi) {
  if (process.env.PI_SUBAGENT_CHILD === "1" && process.env.SPIKE_HOLD_CHILD_START === "1") {
    appendFileSync(process.env.SPIKE_HOLD_READY, `${process.pid}\n`);
    while (!existsSync(process.env.SPIKE_HOLD_GATE)) await new Promise(resolve => setTimeout(resolve, 25));
  }
  pi.registerMcpServer("fixture", { url: `${process.env.SPIKE_GATEWAY}/mcp`, exposure: "codemode", toolExposure: { read: "direct" } });
  pi.on("session_start", (_event, ctx) => appendFileSync(process.env.SPIKE_TRACE,
    JSON.stringify({ session: ctx.sessionManager.getSessionId(), pid: process.pid, child: process.env.PI_SUBAGENT_CHILD === "1" }) + "\n"));
  pi.registerTool({ name: "probe_read", label: "Read fixture", description: "Read a synthetic fixture", parameters: Type.Object({}),
    annotations: { readOnlyHint: true }, execute: async () => ({ content: [{ type: "text", text: "READ_OK" }], details: undefined }) });
  pi.registerTool({ name: "probe_cwd", label: "Working directory", description: "Report the session working directory", parameters: Type.Object({}),
    annotations: { readOnlyHint: true }, execute: async (_id, _params, _signal, _update, ctx) => ({ content: [{ type: "text", text: `CWD:${ctx.cwd}` }], details: undefined }) });
  pi.registerTool({ name: "probe_mutate", label: "Write fixture", description: "Mutate a synthetic canary", parameters: Type.Object({}),
    annotations: { destructiveHint: true }, execute: async () => { writeFileSync(process.env.SPIKE_CANARY, "MUTATED");
      return { content: [{ type: "text", text: "MUTATED" }], details: undefined }; } });
}
