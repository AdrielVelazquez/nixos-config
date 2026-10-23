import { appendFileSync, writeFileSync } from "node:fs";
import { randomUUID } from "node:crypto";

export default async function (pi) {
  const { registerRequiredChildExtensions } = await import(`${process.env.SPIKE_PACKAGE}/src/api/required-child-extensions.js`);
  const { registerSubagentCapabilityCeiling } = await import(`${process.env.SPIKE_PACKAGE}/src/api/capability-ceiling.js`);
  let registration;
  const required = () => [{ id: "provider", path: process.env.SPIKE_PROVIDER }, { id: "probe", path: process.env.SPIKE_PROBE },
    ...(process.env.SPIKE_HEADROOM ? [{ id: "headroom", path: process.env.SPIKE_HEADROOM }] : []),
    ...JSON.parse(process.env.SPIKE_CAPABILITIES || "[]")];
  const register = (ctx, extensions = required()) => {
    registration?.dispose();
    registration = registerRequiredChildExtensions({ sessionId: ctx.sessionManager.getSessionId(), requireForAllRunners: true, extensions });
  };
  pi.on("session_start", async (_event, ctx) => {
    register(ctx);
    if (process.env.SPIKE_PROXY_CAPTURE) writeFileSync(process.env.SPIKE_PROXY_CAPTURE,
      JSON.stringify({ url: process.env.HEADROOM_PROXY_URL, root: process.env.HEADROOM_PI_STATE_DIR }));
    const result = await ctx.modelRegistry.refresh({ force: true, allowNetwork: true, providers: ["llm-platform"] });
    if (result.errors?.size) throw new Error([...result.errors.values()].map(error => error.message).join("; "));
  });
  pi.on("session_shutdown", () => registration?.dispose());
  pi.events.on("subagent:async-started", event => {
    if (process.env.SPIKE_ADMISSIONS) appendFileSync(process.env.SPIKE_ADMISSIONS, JSON.stringify(event) + "\n");
  });
  pi.registerCommand("holdchildren", { description: "Delay fixture child initialization", handler: async () => {
    process.env.SPIKE_HOLD_CHILD_START = "1";
  } });
  pi.registerCommand("spike", { description: "Synthetic compatibility probe", handler: async (args, ctx) => {
    const [mode, agent = "scout", ...task] = args.split(" ");
    let ceiling;
    if (mode === "failrequired") register(ctx, [...required(), { id: "intentional-failure", path: process.env.SPIKE_FAILURE }]);
    if (mode === "ceiling") ceiling = registerSubagentCapabilityCeiling({ sessionId: ctx.sessionManager.getSessionId(), source: "fixture", ceiling: { denyExtensions: true } });
    const requestId = randomUUID(), foreground = ["foreground", "failrequired", "ceiling"].includes(mode);
    let response;
    try { response = await new Promise((resolve, reject) => {
      const responseEvent = foreground ? "prompt-template:subagent:response" : `subagents:rpc:v1:reply:${requestId}`;
      const timeout = setTimeout(() => { off(); reject(new Error("routing fixture timeout")); }, 40000);
      const off = pi.events.on(responseEvent, reply => {
        if (reply.requestId !== requestId) return;
        off(); clearTimeout(timeout); resolve(reply);
      });
      if (foreground) pi.events.emit("prompt-template:subagent:request", {
        requestId, ownerRunId: "fixture", nodeId: requestId, agent, task: task.join(" ") || "SIMPLE", context: "fresh",
        cwd: ctx.cwd, timeoutMs: 15000, intercomBridge: { mode: "off" }, result: { kind: "text" },
      });
      else pi.events.emit("subagents:rpc:v1:request", { version: 1, requestId, method: mode === "async" ? "spawn" : mode,
        params: mode === "async" ? { agent, task: task.join(" ") || "SIMPLE", context: "fresh", async: true, cwd: ctx.cwd }
          : mode === "resume" ? { id: agent, message: task.join(" ") || "RESUME" } : { id: agent } });
    }); } finally { ceiling?.dispose(); if (mode === "failrequired") register(ctx); }
    writeFileSync(process.env.SPIKE_RESULT, JSON.stringify(response));
  } });
}
