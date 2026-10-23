// The upstream status tool is read-only and does not start configured servers.
// Contribute to the visual owner's status map; never take ownership of its footer.
export function createLspStatus(pi, upstream, { enabled = true } = {}) {
  let statusTool;
  const proxy = new Proxy(pi, {
    get(target, key) {
      if (key === "registerTool") return tool => {
        if (tool.name === "lsp_status") statusTool = tool;
        return target.registerTool(tool);
      };
      return Reflect.get(target, key);
    },
  });
  upstream(proxy);
  if (!enabled) return;
  const refresh = async (_event, ctx) => {
    if (!statusTool) return;
    try {
      const result = await statusTool.execute("footer-status", { all: true }, ctx.signal, undefined, ctx);
      const rows = result.structuredContent?.servers ?? [];
      const active = rows.filter(row => !["configured", "stopped", "disabled"].includes(row.state));
      const label = active.length
        ? active.map(row => `${row.server_id} ${row.state === "running" ? "●" : row.state === "starting" ? "◌" : "!"}`).join(" · ")
        : `${rows.length} configured`;
      ctx.ui.setStatus("lsp", `LSP ${label}`);
    } catch {
      ctx.ui.setStatus("lsp", "LSP status unavailable");
    }
  };
  for (const event of ["session_start", "tool_result", "agent_end"]) pi.on(event, refresh);
  pi.on("session_shutdown", (_event, ctx) => ctx.ui.setStatus("lsp", undefined));
}
