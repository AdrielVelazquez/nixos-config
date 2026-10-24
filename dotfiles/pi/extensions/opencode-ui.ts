import {
  VERSION,
  AssistantMessageComponent,
  BashExecutionComponent,
  CustomEditor,
  UserMessageComponent,
  type ExtensionAPI,
  type ExtensionContext,
  type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import { backgroundAnsi, foregroundAnsi, mixColors, truncateToWidth, visibleWidth, wrapTextWithAnsi, type EditorTheme, type TUI } from "@earendil-works/pi-tui";
import {
  diffBlock,
  dropColumns,
  formatDuration,
  formatTokens,
  indent,
  paint,
  parseDiff,
  restyleFences,
  shellBlock,
  shortenPath,
  spread,
  splitShellFailure,
  stripAnsi,
} from "./opencode-ui-core.ts";

// OpenCode-style skin: a left-bar prompt panel, a one-row footer, left-bar user messages, answer footers,
// inline tool lines and filled bash/diff blocks. Everything that Pi lets an extension own (editor, footer,
// tool renderers) uses the public API; the message transcript has no hook, so the two message components
// are decorated through their exported render methods, as neutral-foreground does for Markdown.

type Theme = ExtensionContext["ui"]["theme"];
type Render = (this: unknown, width: number) => string[];
const TEXT_COLUMN = 3;
const BAR = "┃";

let current: ExtensionContext | undefined;
// Every live session in this process (the primary one and in-process children) shares the two prototype patches.
const owners = new Map<object, ExtensionContext>();
let running = false;
let runStartedAt = 0;
const durations = new Map<number, number>();
const patches: { prototype: { render: Render }; original: Render; wrapped: Render }[] = [];

const theme = (): Theme | undefined => current?.ui.theme;
const mode = (t: Theme) => t.getColorMode();
const panelBg = (t: Theme) => t.getBgAnsi("userMessageBg");
const barFg = (t: Theme) => t.getFgAnsi("borderAccent");

function tint(t: Theme, accent: "toolDiffAdded" | "toolDiffRemoved", amount: number): string {
  return backgroundAnsi(mixColors(t.colors.toolSuccessBg, t.colors[accent], amount), mode(t));
}

// ---------------------------------------------------------------------------------------------------------
// Prompt panel

class PanelEditor extends CustomEditor {
  constructor(tui: TUI, editorTheme: EditorTheme, keybindings: KeybindingsManager) {
    super(tui, editorTheme, keybindings, { paddingX: 2 });
  }
  // Pi applies its own editor padding after construction; the panel keeps a fixed indent so text lines up with the transcript.
  setPaddingX(): void {
    super.setPaddingX(2);
  }
  // The border rows become panel padding; only the scroll indicators survive as right-aligned hints.
  renderTopBorder(width: number, hidden: number): string {
    return hidden > 0 ? " ".repeat(Math.max(0, width - 12)) + `↑ ${hidden} more ` : "";
  }
  renderBottomBorder(width: number, hidden: number): string {
    return hidden > 0 ? " ".repeat(Math.max(0, width - 12)) + `↓ ${hidden} more ` : "";
  }
  private meta(t: Theme): string {
    const text = this.getText();
    if (text.startsWith("!")) {
      const local = text.startsWith("!!");
      return t.fg("bashMode", t.bold("shell")) + t.fg("dim", local ? "  output stays local" : "  output goes to the model");
    }
    const model = current?.model;
    if (!model) return t.fg("dim", "no model selected");
    const level = current?.thinkingLevel ?? "off";
    const token = ({ off: "thinkingOff", minimal: "thinkingMinimal", low: "thinkingLow", medium: "thinkingMedium", high: "thinkingHigh", xhigh: "thinkingXhigh", max: "thinkingMax" } as const)[level as "off"] ?? "thinkingOff";
    return [
      t.fg("text", model.name || model.id),
      t.fg("dim", model.provider),
      model.reasoning && level !== "off" ? t.fg(token, level) : "",
    ]
      .filter(Boolean)
      .join("  ");
  }
  private shift = 0;
  render(width: number): string[] {
    const t = theme();
    if (!t || width < 8) return super.render(width);
    const inner = width - 1;
    const lines = super.render(inner);
    const count = (this as any).renderedVisibleLineCount as number;
    const bg = panelBg(t);
    const bar = (text: string) => barFg(t) + bg + BAR + "\x1b[39m" + paint(text, inner, bg);
    const hint = (line: string) => (stripAnsi(line).trim() ? t.fg("dim", stripAnsi(line).trim()) : "");
    const rows = [bar(hint(lines[0])), ...lines.slice(1, 1 + count).map(bar)];
    const below = hint(lines[1 + count] ?? "");
    if (below) rows.push(bar(below));
    rows.push(bar(""), bar("  " + this.meta(t)));
    const edge = barFg(t) + "╹\x1b[39m" + foregroundAnsi(t.colors.userMessageBg, mode(t)) + "▀".repeat(inner) + "\x1b[39m";
    // Rows between the text and the autocomplete list: the base editor has one bottom border, the panel has
    // the optional scroll hint, a gap, the model row and the edge.
    this.shift = 2 + (below ? 1 : 0);
    return [...rows, edge, ...lines.slice(2 + count).map((line) => " " + line)];
  }
  // The bar takes the first column and the extra rows push the autocomplete list down.
  handleMouse(event: Parameters<NonNullable<CustomEditor["handleMouse"]>>[0]) {
    const count = (this as any).renderedVisibleLineCount as number;
    const y = event.y > count + 1 + this.shift ? event.y - this.shift : event.y;
    return super.handleMouse?.({ ...event, x: Math.max(0, event.x - 1), width: Math.max(1, event.width - 1), y });
  }
}

// ---------------------------------------------------------------------------------------------------------
// Footer

let costCache: { count: number; sessionId: string; cost: number } | undefined;
function sessionCost(ctx: ExtensionContext): number {
  const manager = ctx.sessionManager as any;
  if (!manager) return 0;
  const count = manager.getEntryCount?.() ?? -1;
  const sessionId = manager.getSessionId?.() ?? "";
  if (costCache && costCache.count === count && costCache.sessionId === sessionId) return costCache.cost;
  let cost = 0;
  for (const entry of manager.getEntries() as any[]) {
    if (entry.type === "message" && entry.message?.role === "assistant") cost += entry.message.usage?.cost?.total ?? 0;
    else if (entry.type === "usage") cost += entry.usage?.cost?.total ?? 0;
  }
  costCache = { count, sessionId, cost };
  return cost;
}

function footer(tui: TUI, _theme: unknown, data: { getGitBranch(): string | null; getExtensionStatuses(): ReadonlyMap<string, string>; onBranchChange(cb: () => void): () => void }) {
  const unsubscribe = data.onBranchChange(() => tui.requestRender());
  return {
    invalidate() {},
    dispose: unsubscribe,
    render(width: number): string[] {
      const ctx = current;
      const t = theme();
      if (!ctx || !t) return [];
      const home = process.env.HOME;
      const branch = data.getGitBranch();
      const left = " " + t.fg("muted", shortenPath(ctx.cwd, undefined, home)) + (branch ? t.fg("dim", " · ") + t.fg("muted", branch) : "");
      const usage = ctx.getContextUsage();
      // Highest priority first: when the row is too narrow the tail (extension statuses, then cost) is dropped
      // before the path or branch is cut.
      const parts: string[] = [];
      if (running) parts.push(t.fg("text", "esc") + t.fg("muted", " interrupt"));
      if (usage?.tokens != null) {
        const pct = usage.percent ?? 0;
        const shade = pct > 90 ? "error" : pct > 70 ? "warning" : "muted";
        parts.push(t.fg(shade, `${formatTokens(usage.tokens)} (${Math.round(pct)}%)`));
      }
      const cost = sessionCost(ctx);
      if (cost > 0) parts.push(t.fg("muted", `$${cost.toFixed(2)}`));
      for (const status of data.getExtensionStatuses().values()) {
        const clean = status.replace(/[\r\n\t]+/g, " ").trim();
        if (clean) parts.push(clean.includes("\x1b") ? clean : t.fg("muted", clean));
      }
      const join = (items: string[]) => (items.length ? items.join(t.fg("dim", "  ·  ")) + " " : "");
      while (parts.length > 1 && visibleWidth(left) + 3 + visibleWidth(join(parts)) > width) parts.pop();
      const right = join(parts);
      return [spread(left, right, width)];
    },
  };
}

// ---------------------------------------------------------------------------------------------------------
// Header

function header() {
  return {
    invalidate() {},
    render(width: number): string[] {
      const t = theme();
      if (!t) return [];
      const key = (name: string, label: string) => t.fg("text", name) + t.fg("dim", " " + label);
      const hints = [key("esc", "interrupt"), key("/", "commands"), key("!", "shell"), key("ctrl+o", "expand"), key("ctrl+c", "clear")].join(t.fg("dim", "  ·  "));
      return [
        "",
        " ".repeat(TEXT_COLUMN) + t.fg("accent", t.bold("π")) + "  " + t.bold(t.fg("text", "pi")) + " " + t.fg("dim", `v${VERSION}`),
        truncateToWidth(" ".repeat(TEXT_COLUMN) + hints, width, "…"),
        "",
      ];
    },
  };
}

// ---------------------------------------------------------------------------------------------------------
// Messages

function userBar(line: string, t: Theme): string {
  const bg = panelBg(t);
  return barFg(t) + bg + BAR + "\x1b[39m" + bg + " \x1b[49m" + line;
}

/** For each assistant message, the model of the turn before it when that differs; cached per session length. */
let switchCache: { count: number; sessionId: string; map: Map<number, string> } | undefined;
function modelSwitches(ctx: ExtensionContext): Map<number, string> {
  const manager = ctx.sessionManager as any;
  if (!manager) return new Map();
  const count = manager.getEntryCount?.() ?? -1;
  const sessionId = manager.getSessionId?.() ?? "";
  if (switchCache && switchCache.count === count && switchCache.sessionId === sessionId) return switchCache.map;
  const map = new Map<number, string>();
  let last: string | undefined;
  for (const entry of manager.getEntries() as any[]) {
    const message = entry.type === "message" ? entry.message : undefined;
    if (message?.role !== "assistant" || !message.model) continue;
    const key = `${message.provider ?? "?"}/${message.model}`;
    if (last && last !== key) map.set(message.timestamp, last);
    last = key;
  }
  switchCache = { count, sessionId, map };
  return map;
}

function answerFooter(component: any, t: Theme): string[] {
  const message = component.lastMessage;
  if (!message || component.isStreaming || component.hasToolCalls) return [];
  if (!["stop", "length", "aborted", "error"].includes(message.stopReason)) return [];
  const name = current?.modelRegistry?.find?.(message.provider, message.model)?.name ?? message.model;
  const took = durations.get(message.timestamp);
  const end = message.stopReason === "aborted" ? "interrupted" : message.stopReason === "error" ? "failed" : "";
  const from = current ? modelSwitches(current).get(message.timestamp) : undefined;
  const detail = [
    ...[name, took !== undefined ? formatDuration(took) : "", end].filter(Boolean).map((part) => t.fg("muted", part)),
    from ? t.fg("warning", `switched from ${from}`) : "",
  ]
    .filter(Boolean)
    .join(t.fg("dim", " · "));
  return ["", " ".repeat(TEXT_COLUMN) + t.fg("borderAccent", "▣") + "  " + detail];
}

function install() {
  if (patches.length) return;
  const wrap = (prototype: { render: Render }, render: (original: Render) => Render) => {
    const original = prototype.render;
    if (typeof original !== "function") return;
    const wrapped = render(original);
    patches.push({ prototype, original, wrapped });
    prototype.render = wrapped;
  };
  wrap(UserMessageComponent.prototype as any, (original) =>
    function (this: unknown, width: number) {
      const t = theme();
      if (!t || width < 8) return original.call(this, width);
      return original.call(this, width - 2).map((line) => userBar(line, t));
    });
  // `!command` output: Pi frames it between two coloured rules; here it joins the filled panels, keeping the
  // command in its shell colour so it reads as yours and not the model's.
  wrap(BashExecutionComponent.prototype as any, (original) =>
    function (this: unknown, width: number) {
      const t = theme();
      if (!t || width < 12) return original.call(this, width);
      const inner = original
        .call(this, width - TEXT_COLUMN - 1)
        .filter((line) => !/^─+$/.test(stripAnsi(line).trim()))
        .map((line) => dropColumns(line, 1));
      while (inner.length && !stripAnsi(inner[0]).trim()) inner.shift();
      const bg = t.getBgAnsi("toolSuccessBg");
      const row = (line: string) => paint(" ".repeat(TEXT_COLUMN) + line, width, bg);
      return ["", row(""), ...inner.map(row), row("")];
    });
  wrap(AssistantMessageComponent.prototype as any, (original) =>
    function (this: unknown, width: number) {
      const t = theme();
      if (!t || width < 8) return original.call(this, width);
      const lines = indent(original.call(this, width - (TEXT_COLUMN - 1)), TEXT_COLUMN - 1);
      const fenced = restyleFences(lines, width, t.getBgAnsi("toolSuccessBg"), (lang) => t.fg("dim", lang));
      return [...fenced, ...answerFooter(this, t)];
    });
}

// ---------------------------------------------------------------------------------------------------------
// Tools

// A renderer that throws must not take the transcript down, and must not vanish silently either.
class Rows {
  constructor(private readonly build: (width: number) => string[]) {}
  render(width: number): string[] {
    try {
      return this.build(width);
    } catch (error) {
      const t = theme();
      const message = `render failed: ${error instanceof Error ? error.message : String(error)}`;
      return [truncateToWidth(" ".repeat(TEXT_COLUMN) + (t ? t.fg("error", message) : message), Math.max(1, width), "…")];
    }
  }
  invalidate() {}
}

const text = (value: unknown): string => (typeof value === "string" ? value : "");
const pathOf = (args: any): string => text(args?.file_path ?? args?.path);
const outputOf = (result: any): string =>
  (result?.content ?? []).filter((part: any) => part.type === "text").map((part: any) => part.text ?? "").join("\n");

interface Inline {
  icon: string;
  verb: string;
  target: (args: any, cwd: string) => string;
  extra?: (args: any) => string;
  note?: (args: any) => string;
  count?: (output: string, details: any) => string;
}
const plural = (n: number, noun: string) =>
  `${n} ${n === 1 ? noun : /(ch|sh|s|x)$/.test(noun) ? noun + "es" : /[^aeiou]y$/.test(noun) ? noun.slice(0, -1) + "ies" : noun + "s"}`;
const lineCount = (noun: string, detailKey?: string) => (output: string, details: any) => {
  // Tools that report their own count (hashline's grep) are trusted over counting printed lines.
  if (detailKey && Number.isFinite(details?.[detailKey])) return plural(details[detailKey], noun);
  if (/^No \w+/i.test(output.trim())) return plural(0, noun);
  const n = output.split("\n").filter((line) => line.trim() && !line.startsWith("[") && line !== "--").length;
  return n ? plural(n, noun) : "";
};
const INLINE: Record<string, Inline> = {
  read: {
    icon: "→",
    verb: "Read",
    target: (a, cwd) => shortenPath(pathOf(a), cwd, process.env.HOME),
    extra: (a) => [a?.offset != null ? `offset=${a.offset}` : "", a?.limit != null ? `limit=${a.limit}` : ""].filter(Boolean).join(", "),
  },
  ls: { icon: "→", verb: "List", target: (a, cwd) => shortenPath(text(a?.path) || cwd, cwd, process.env.HOME), count: lineCount("entry") },
  grep: {
    icon: "✱",
    verb: "Grep",
    target: (a, cwd) => `"${text(a?.pattern)}"` + (a?.path ? ` in ${shortenPath(text(a.path), cwd, process.env.HOME)}` : ""),
    count: lineCount("match", "matches"),
  },
  find: {
    icon: "✱",
    verb: "Glob",
    target: (a, cwd) => `"${text(a?.pattern)}"` + (a?.path ? ` in ${shortenPath(text(a.path), cwd, process.env.HOME)}` : ""),
    count: lineCount("file", "files"),
  },
  write: {
    icon: "←",
    verb: "Write",
    target: (a, cwd) => shortenPath(pathOf(a), cwd, process.env.HOME),
    note: (a) => {
      const n = text(a?.content) ? text(a.content).split("\n").length - (text(a.content).endsWith("\n") ? 1 : 0) : 0;
      return n ? plural(n, "line") : "";
    },
  },
  edit: { icon: "←", verb: "Edit", target: (a, cwd) => shortenPath(pathOf(a), cwd, process.env.HOME) },
};

function inlineRow(t: Theme, kind: Inline, args: any, ctx: any, shown: { suffix?: string }, width: number): string {
  const failed = ctx.isError;
  const icon = ctx.isPartial ? t.fg("dim", "⋯") : failed ? t.fg("error", "✗") : t.fg("muted", kind.icon);
  const extra = kind.extra?.(args);
  const note = kind.note?.(args) || shown.suffix;
  const suffix = [extra ? `[${extra}]` : "", note ? `(${note})` : ""].filter(Boolean).join(" ");
  const row = " ".repeat(TEXT_COLUMN) + icon + " " + t.fg("muted", kind.verb) + " " + t.fg("text", kind.target(args, ctx.cwd)) + (suffix ? " " + t.fg("dim", suffix) : "");
  return truncateToWidth(row, width, "…");
}

function errorRows(t: Theme, output: string, width: number): string[] {
  const room = Math.max(1, width - TEXT_COLUMN - 2);
  const visual = output.trim().split("\n").filter(Boolean).flatMap((line) => wrapTextWithAnsi(t.fg("error", line), room));
  const shown = visual.slice(0, 4);
  if (visual.length > shown.length) shown.push(t.fg("dim", `… ${visual.length - shown.length} more lines`));
  return indent(shown, TEXT_COLUMN + 2);
}

type NativeRenderers = { renderShell?: string; renderCall?: (...a: any[]) => any; renderResult?: (...a: any[]) => any } | undefined;

/**
 * Tools from other extensions keep their own call and result renderers, but sit in the same filled panel as
 * bash. The call component draws the whole panel so its background stays continuous while the result arrives.
 */
function genericPanel(name: string, native: NativeRenderers): NativeRenderers {
  if (native?.renderShell === "self") return native;
  return {
    renderShell: "self",
    renderCall(args: any, t: Theme, ctx: any) {
      const state = ctx.state as { call?: any; result?: any; resultContext?: any };
      return new Rows((width) => {
        const bg = t.getBgAnsi(ctx.isPartial ? "toolPendingBg" : ctx.isError ? "toolErrorBg" : "toolSuccessBg");
        const inner = Math.max(1, width - TEXT_COLUMN - 2);
        let head: string[];
        try {
          state.call = native?.renderCall ? native.renderCall(args, t, { ...ctx, lastComponent: state.call }) : undefined;
          head = state.call ? state.call.render(inner) : [];
        } catch {
          head = [];
        }
        if (!head.length) head = [truncateToWidth(t.fg("muted", name) + " " + t.fg("dim", compactArgs(args)), inner, "…")];
        let body: string[] = [];
        try {
          if (state.result) body = state.result.render(inner);
        } catch {
          body = [];
        }
        const row = (line: string) => paint(" ".repeat(TEXT_COLUMN) + line, width, bg);
        return [row(""), ...head.map(row), ...(body.length ? [row(""), ...body.map(row)] : []), row("")];
      });
    },
    renderResult(result: any, options: any, t: Theme, ctx: any) {
      const state = ctx.state as { result?: any };
      try {
        state.result = native?.renderResult
          ? native.renderResult(result, options, t, { ...ctx, lastComponent: state.result })
          : new Rows((width) => indent(wrapTextWithAnsi(t.fg("muted", outputOf(result)), width), 0).slice(0, options.expanded ? 400 : 12));
      } catch {
        state.result = undefined;
      }
      return new Rows(() => []);
    },
  };
}

function compactArgs(args: any): string {
  try {
    const parts = Object.entries(args ?? {}).map(([key, value]) => `${key}=${typeof value === "string" ? value : JSON.stringify(value)}`);
    return parts.join(" ").replace(/\s+/g, " ");
  } catch {
    return "";
  }
}

function renderersFor(name: string, next: () => any) {
  const kind = INLINE[name];
  const native = next();
  const hint = () => "ctrl+o to expand";
  const base = { renderShell: "self" as const };

  if (name === "bash") {
    return {
      ...base,
      renderCall(args: any, t: Theme, ctx: any) {
        return new Rows((width) => {
          const state = ctx.state as { output?: string; failed?: string; pending?: boolean };
          const split = splitShellFailure(state.output ?? "");
          return shellBlock(
            {
              command: text(args?.command),
              output: split.output,
              failure: ctx.isError ? split.failure ?? (split.output ? undefined : "failed") : undefined,
              expanded: ctx.expanded,
              maxLines: 10,
              pending: ctx.isPartial,
              duration: ctx.durationMs,
              hint: hint(),
            },
            width,
            { bg: t.getBgAnsi(ctx.isPartial ? "toolPendingBg" : "toolSuccessBg"), fg: (token, value) => t.fg(token, value) },
          );
        });
      },
      renderResult(result: any, _options: any, _t: Theme, ctx: any) {
        (ctx.state as any).output = outputOf(result);
        return new Rows(() => []);
      },
    };
  }

  if (!kind) return genericPanel(name, native);

  return {
    ...base,
    renderCall(args: any, t: Theme, ctx: any) {
      return new Rows((width) => {
        const state = ctx.state as { suffix?: string };
        return [inlineRow(t, kind, args, ctx, state, width)];
      });
    },
    renderResult(result: any, options: any, t: Theme, ctx: any) {
      const output = outputOf(result);
      const state = ctx.state as { suffix?: string };
      state.suffix = ctx.isError ? undefined : kind.count?.(output, result?.details);
      if (ctx.isError) return new Rows((width) => errorRows(t, output, width));
      if (name === "edit") {
        const details = result?.details ?? {};
        const rows = parseDiff(text(details.diff));
        const warnings: string[] = Array.isArray(details.warnings) ? details.warnings.map(text).filter(Boolean) : [];
        return new Rows((width) => {
          const style = {
            fg: (token: any, value: string) => t.fg(token, value),
            bgs: { ctx: t.getBgAnsi("toolSuccessBg"), add: tint(t, "toolDiffAdded", 0.16), del: tint(t, "toolDiffRemoved", 0.18) },
          };
          const block = diffBlock(rows, width - 2, style, options.expanded ? 400 : 18);
          const hidden = rows.length - 18;
          const more = !options.expanded && hidden > 0 ? [" ".repeat(TEXT_COLUMN) + t.fg("dim", `… ${hidden} more diff lines · ${hint()}`)] : [];
          const notes = warnings.map((line) => " ".repeat(TEXT_COLUMN) + t.fg("warning", truncateToWidth(line, width - TEXT_COLUMN, "…")));
          return [...indent(block, 2), ...more, ...notes];
        });
      }
      if (options.expanded && native?.renderResult && (name === "read" || name === "write")) {
        const inner = native.renderResult(result, options, t, ctx);
        return new Rows((width) => indent(inner.render(width - TEXT_COLUMN), TEXT_COLUMN));
      }
      return new Rows(() => []);
    },
  };
}

// ---------------------------------------------------------------------------------------------------------
// Wiring

export default function (pi: ExtensionAPI) {
  const owner = {};
  pi.registerToolRenderer((name, next) => renderersFor(name, next as () => any) as any);

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    owners.set(owner, ctx);
    current = ctx;
    install();
    ctx.ui.setEditorComponent((tui, editorTheme, keybindings) => new PanelEditor(tui, editorTheme, keybindings));
    ctx.ui.setFooter(footer as any);
    ctx.ui.setHeader(header);
  });
  pi.on("agent_start", () => {
    running = true;
    runStartedAt = Date.now();
  });
  pi.on("agent_end", () => {
    running = false;
  });
  pi.on("message_end", (event) => {
    const message = event.message as any;
    if (message?.role === "assistant" && runStartedAt) durations.set(message.timestamp, Date.now() - runStartedAt);
  });
  pi.on("session_shutdown", () => {
    if (!owners.delete(owner)) return;
    current = [...owners.values()].at(-1);
    if (owners.size) return;
    for (const { prototype, original, wrapped } of patches) if (prototype.render === wrapped) prototype.render = original;
    patches.length = 0;
    durations.clear();
    switchCache = undefined;
    costCache = undefined;
  });
}
