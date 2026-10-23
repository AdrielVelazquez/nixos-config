import { basename } from "node:path";
import { stripTerminalSequences, truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";
import type { ExtensionAPI, ExtensionContext, ReadonlyFooterDataProvider, Theme } from "@earendil-works/pi-coding-agent";

const plain = (value: unknown) => stripTerminalSequences(String(value ?? "")).replace(/[\x00-\x1f\x7f]/g, " ");
const amount = (value: number) => value >= 1000 ? `${(value / 1000).toFixed(1)}k` : String(value);

/** One visual owner; no tool definitions, model calls, polling, or settings writes. */
export function installVisuals(pi: ExtensionAPI, zentui: (api: ExtensionAPI) => void) {
  zentui(new Proxy(pi, { get(target, key) {
    if (key === "registerTool") return () => { throw new Error("Visuals must not replace tool execution"); };
    if (key === "registerCommand" || key === "registerShortcut") return () => {};
    return Reflect.get(target, key);
  } }));

  let active = false, footerData: ReadonlyFooterDataProvider | undefined, state = {
    cwd: "", project: "", model: "", provider: "", thinking: "", status: "READY",
    context: null as number | null, input: 0, output: 0, cache: 0, cacheWrite: 0, tools: 0, cost: 0,
  };
  const views = new Set<{ requestRender(): void }>();
  const refresh = (ctx: ExtensionContext, status?: string) => {
    if (!active || ctx.mode !== "tui") return;
    let input = 0, output = 0, cache = 0, cacheWrite = 0, tools = 0, cost = 0;
    for (const entry of ctx.sessionManager.getEntries()) {
      if (entry.type !== "message") continue;
      const message = entry.message;
      if (message.role === "toolResult") tools++;
      if (message.role !== "assistant") continue;
      input += message.usage?.input ?? 0;
      output += message.usage?.output ?? 0;
      cache += message.usage?.cacheRead ?? 0;
      cacheWrite += message.usage?.cacheWrite ?? 0;
      cost += message.usage?.cost?.total ?? 0;
    }
    state = { cwd: plain(ctx.cwd), project: plain(basename(ctx.cwd) || ctx.cwd),
      model: plain(ctx.model?.id ?? "No model selected"), provider: plain(ctx.model?.provider),
      thinking: plain(ctx.thinkingLevel ?? pi.getThinkingLevel()), status: status ?? state.status,
      context: ctx.getContextUsage()?.percent ?? null, input, output, cache, cacheWrite, tools, cost };
    for (const tui of views) tui.requestRender();
  };
  const mode = () => {
    const value = plain(footerData?.getExtensionStatuses().get("managed-routing"));
    return /^(build|plan)\b/i.exec(value)?.[1].toUpperCase() ?? "SESSION";
  };
  const proxy = () => process.env.LLM_PLATFORM_INFERENCE_PROXY_REQUIRED === "1" ? "HEADROOM REQUIRED" : "NO PROXY CONTRACT";
  const panel = (theme: Theme, width: number, content: string[]) => {
    if (width < 8) return content.map(line => truncateToWidth(line, Math.max(width, 1)));
    const inner = width - 4, edge = (text: string) => theme.fg("borderMuted", text);
    return [edge("╭" + "─".repeat(width - 2) + "╮"), ...content.map(line => {
      const fitted = truncateToWidth(line, inner);
      return edge("│ ") + fitted + " ".repeat(Math.max(0, inner - visibleWidth(fitted))) + edge(" │");
    }), edge("╰" + "─".repeat(width - 2) + "╯")];
  };
  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui" || !ctx.hasUI) return;
    active = true; refresh(ctx, "READY");
    ctx.ui.setFooter((tui, theme, data) => {
      views.add(tui); footerData = data;
      const offBranch = data.onBranchChange(() => tui.requestRender());
      return { invalidate() {}, dispose() { offBranch(); views.delete(tui); }, render(width: number) {
        const cachedInput = state.input + state.cache + state.cacheWrite;
        const hit = cachedInput ? `${Math.round(state.cache / cachedInput * 100)}%` : "—";
        const context = state.context === null ? "—" : `${state.context.toFixed(1)}%`;
        const stateColor = state.status === "ERROR" ? "error" : state.status === "NEEDS INPUT" ? "warning" : "accent";
        const top = `${theme.fg("accent", mode())} · ${state.thinking}  │  CONTEXT ${context}  │  CACHE ${hit}  │  ${theme.fg(stateColor, state.status)}`;
        const usage = `IN ${amount(state.input)}  OUT ${amount(state.output)}  TOOLS ${state.tools}${state.cost > 0 ? `  $${state.cost.toFixed(3)}` : ""}  │  ${proxy()}`;
        const statuses = [...data.getExtensionStatuses().values()].map(plain).filter(Boolean).join("  ·  ");
        return [theme.fg("borderMuted", "─".repeat(Math.max(1, width))),
          ...wrapTextWithAnsi(top, Math.max(1, width)),
          ...wrapTextWithAnsi(theme.fg("muted", usage), Math.max(1, width)),
          ...(statuses ? wrapTextWithAnsi(theme.fg("muted", statuses), Math.max(1, width)) : [])];
      } };
    });
    ctx.ui.setHeader((tui, theme) => {
      views.add(tui);
      return { invalidate() {}, dispose() { views.delete(tui); }, render(width: number) {
        const branch = plain(footerData?.getGitBranch());
        return panel(theme, width, [
          theme.bold(theme.fg("accent", `π  PI WORKSPACE  ·  ${state.project}  [${mode()}]`)),
          theme.fg("muted", `${state.cwd}${branch ? `  ·  ${branch}` : ""}`),
          `${theme.fg("text", state.model)}  ·  ${state.thinking}  ·  ${theme.fg("dim", state.provider)}  ·  ${proxy()}`,
        ]);
      } };
    });
  });
  pi.on("agent_start", (_event, ctx) => refresh(ctx, "WORKING"));
  pi.on("ui_prompt_start", (_event, ctx) => refresh(ctx, "NEEDS INPUT"));
  pi.on("ui_prompt_end", (_event, ctx) => refresh(ctx, ctx.isIdle() ? "READY" : "WORKING"));
  pi.on("agent_settled", (_event, ctx) => {
    if (!active) return;
    const last = ctx.sessionManager.getEntries().filter(entry => entry.type === "message" && entry.message.role === "assistant").at(-1);
    const reason = last?.type === "message" && last.message.role === "assistant" ? last.message.stopReason : undefined;
    refresh(ctx, reason === "error" ? "ERROR" : reason === "aborted" ? "INTERRUPTED" : "READY");
  });
  pi.on("model_select", (_event, ctx) => { refresh(ctx); });
  pi.on("thinking_level_select", (_event, ctx) => { refresh(ctx); });
  pi.on("session_info_changed", (_event, ctx) => { refresh(ctx); });
  pi.on("session_compact", (_event, ctx) => { refresh(ctx); });
  pi.on("session_tree", (_event, ctx) => { refresh(ctx); });
  pi.on("tool_result", (_event, ctx) => { refresh(ctx); });
  pi.on("session_shutdown", (_event, ctx) => {
    if (active) { ctx.ui.setHeader(undefined); ctx.ui.setFooter(undefined); }
    active = false; footerData = undefined; views.clear();
  });
}
