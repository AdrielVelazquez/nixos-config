import { readFileSync, writeFileSync } from "node:fs";
import { Type } from "typebox";

export default function (pi) {
  pi.on("session_start", () => writeFileSync(process.env.PI_STACK_STATE,
    JSON.stringify({ url: process.env.HEADROOM_PROXY_URL, root: process.env.HEADROOM_PI_STATE_DIR }), { mode: 0o600 }));
  pi.registerTool({ name: "fixture_blob", label: "Synthetic blob", description: "Return synthetic repeated JSON rows",
    parameters: Type.Object({}), execute: async (_id, _input, _signal, _update, ctx) => {
      const content = "synthetic-retrieval-sentinel\n".repeat(150);
      const compressed = await ctx.executeTool("mcp__headroom__headroom_compress", { content });
      if (compressed.isError) throw new Error("Native MCP compression call failed");
      const data = JSON.parse(compressed.result.content.filter(item => item.type === "text").map(item => item.text).join("\n"));
      if (typeof data.hash !== "string") throw new Error("Headroom MCP compression did not return a retrieval hash");
      const retrieved = await ctx.executeTool("mcp__headroom__headroom_retrieve", { hash: data.hash });
      if (retrieved.isError || !JSON.stringify(retrieved.result.content).includes("synthetic-retrieval-sentinel")) throw new Error("Native Headroom MCP retrieval failed");
      const state = JSON.parse(readFileSync(process.env.PI_STACK_STATE, "utf8"));
      writeFileSync(process.env.PI_STACK_STATE, JSON.stringify({ ...state, ccrVerified: true }), { mode: 0o600 });
      return { content: [{ type: "text", text: readFileSync(process.env.PI_STACK_BLOB, "utf8") }], details: undefined };
    } });
  pi.registerCommand("fixture-reload", { description: "Reload fixture resources", handler: async (_args, ctx) => { await ctx.reload(); } });
}
