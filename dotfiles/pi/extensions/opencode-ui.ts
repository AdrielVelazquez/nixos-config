import { execFile } from "node:child_process";
import {
  VERSION,
  AssistantMessageComponent,
  BashExecutionComponent,
  CustomEditor,
  UserMessageComponent,
  getLanguageFromPath,
  highlightCode,
  type ExtensionAPI,
  type ExtensionContext,
  type KeybindingsManager,
} from "@earendil-works/pi-coding-agent";
import { backgroundAnsi, foregroundAnsi, mixColors, truncateToWidth, visibleWidth, wrapTextWithAnsi, type EditorTheme, type TUI } from "@earendil-works/pi-tui";
import {
  activityFill,
  centered,
  describeActivity,
  diffBlock,
  dropColumns,
  footerStatuses,
  formatChanges,
  formatDuration,
  formatTokens,
  highlightCommand,
  highlightDiffRows,
  indent,
  keepForeground,
  logoRows,
  mcpHealth,
  overlayRight,
  paint,
  parseDiff,
  parseMcpAttention,
  restyleFences,
  roleLabel,
  shellBlock,
  shortenPath,
  spread,
  splitShellFailure,
  stripAnsi,
  toastBox,
  turnChanges,
  type McpProblem,
  type Toast,
  type TurnChanges,
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
let activity = "Working";
const waitingQuestions = new Set<string>();
let activityStep = 0;
const durations = new Map<number, number>();
const patches: { prototype: { render: Render }; original: Render; wrapped: Render }[] = [];
// What bash actually ran, by tool call id, for the commands a hook (rtk) rewrote: the transcript shows what the model
// asked for, and `tool_result` is the first place the rewritten input is visible.
const executed = new Map<string, string>();
// Highlighted commands by text: highlighting is too slow to repeat on every frame, and a command never changes.
const commandCache = new Map<string, (string | undefined)[]>();

// Pi keeps MCP connection state private; the startup report it prints is recorded as it passes through `notify`.
const reported = new Map<string, McpProblem>();
// Notifications raised before the first prompt, shown as boxes on the splash.
let toasts: Toast["body"][] = [];
let toastLevels: ("warning" | "error")[] = [];
let splash = false;
let requestHeader: (() => void) | undefined;
let statusData: { getExtensionStatuses(): ReadonlyMap<string, string> } | undefined;
let mcpTools: (() => Set<string>) | undefined;

const theme = (): Theme | undefined => current?.ui.theme;
const mode = (t: Theme) => t.getColorMode();
const panelBg = (t: Theme) => t.getBgAnsi("userMessageBg");
const barFg = (t: Theme) => t.getFgAnsi("borderAccent");

function tint(t: Theme, accent: "toolDiffAdded" | "toolDiffRemoved", amount: number): string {
  return backgroundAnsi(mixColors(t.colors.toolSuccessBg, t.colors[accent], amount), mode(t));
}

// ---------------------------------------------------------------------------------------------------------
// Prompt panel

function splashEnabled(width: number, rows: number): boolean {
  return splash && width >= 24 && rows >= 18;
}

class PanelEditor extends CustomEditor {
  constructor(private readonly splashTui: TUI, editorTheme: EditorTheme, keybindings: KeybindingsManager) {
    super(splashTui, editorTheme, keybindings, { paddingX: 2 });
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
    const agent = roleLabel(statusData ? footerStatuses(statusData.getExtensionStatuses()).role : undefined);
    const dot = t.fg("dim", " · ");
    if (!model) return t.fg(agent === "Build" ? "borderAccent" : "customMessageLabel", t.bold(agent)) + dot + t.fg("dim", "no model selected");
    const level = current?.thinkingLevel ?? "off";
    const token = ({ off: "thinkingOff", minimal: "thinkingMinimal", low: "thinkingLow", medium: "thinkingMedium", high: "thinkingHigh", xhigh: "thinkingXhigh", max: "thinkingMax" } as const)[level as "off"] ?? "thinkingOff";
    return [
      t.fg(agent === "Build" ? "borderAccent" : "customMessageLabel", t.bold(agent)),
      t.fg("text", model.name || model.id) + " " + t.fg("dim", model.provider),
      model.reasoning && level !== "off" ? t.fg(token, level) : "",
    ]
      .filter(Boolean)
      .join(dot);
  }
  private shift = 0;
  private offsetX = 0;
  private offsetY = 0;
  private panelWidth = 0;
  private panelHeight = 0;
  render(width: number, compact = false): string[] {
    const t = theme();
    this.offsetX = this.offsetY = 0;
    this.panelWidth = width;
    if (!t || width < 8) return super.render(width);
    const height = this.splashTui.terminal.rows;
    const home = !compact && splashEnabled(width, height);
    this.panelWidth = home ? Math.min(80, width - 4) : width;
    const inner = this.panelWidth - 1;
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
    let panel = [...rows, edge, ...lines.slice(2 + count).map((line) => " " + line)];
    this.panelHeight = panel.length;
    if (!home) return panel;
    this.offsetX = Math.floor((width - this.panelWidth) / 2);
    panel = panel.map((line) => " ".repeat(this.offsetX) + line);
    const logo = centered(logoRows([
      { text: "p", paint: (s) => t.fg("muted", s) },
      { text: "i", paint: (s) => t.fg("text", s) },
    ]), width);
    const group = [...logo, "", "", ...panel];
    const notifications = splashNotifications(t, width).length;
    if (group.length + notifications + 3 > height) return this.render(width, true);
    const centeredPadding = Math.max(0, Math.floor((height - group.length) / 2) - 1);
    const padding = this.splashTui.mode === "fullscreen"
      ? Math.min(centeredPadding, height - group.length - notifications - 3)
      : Math.max(0, centeredPadding - notifications);
    this.offsetY = logo.length + 2;
    // Fullscreen pins the editor dock to the bottom; trailing space lifts the entire splash group.
    if (this.splashTui.mode === "fullscreen") return [...group, ...Array(padding).fill("")];
    this.offsetY += padding;
    return [...Array(padding).fill(""), ...group];
  }
  // The bar takes the first column and the extra rows push the autocomplete list down.
  handleMouse(event: Parameters<NonNullable<CustomEditor["handleMouse"]>>[0]) {
    const localY = event.y - this.offsetY;
    const localX = event.x - this.offsetX;
    if (localX < 0 || localX >= this.panelWidth || localY < 0 || localY >= this.panelHeight) return;
    const count = (this as any).renderedVisibleLineCount as number;
    const y = localY > count + 1 + this.shift ? localY - this.shift : localY;
    return super.handleMouse?.({ ...event, x: Math.max(0, localX - 1), width: Math.max(1, this.panelWidth - 1), y });
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

// Changed paths in the working tree, shown beside the branch. It is refreshed after tools that can change files, never
// on a timer, and left unknown outside a git work tree. `--no-optional-locks` keeps the probe from fighting the
// agent's own git commands over the index lock.
let dirty: number | undefined;
let dirtyBusy = false;
let dirtyAgain = false;
let requestRender: (() => void) | undefined;
function refreshDirty() {
  const ctx = current;
  if (!ctx) return;
  if (dirtyBusy) {
    dirtyAgain = true;
    return;
  }
  dirtyBusy = true;
  execFile(
    "git",
    ["--no-optional-locks", "status", "--porcelain=v1", "--untracked-files=normal"],
    { cwd: ctx.cwd, timeout: 4000, maxBuffer: 4 * 1024 * 1024 },
    (error, stdout) => {
      dirtyBusy = false;
      const next = error ? undefined : stdout.split("\n").filter(Boolean).length;
      if (next !== dirty) {
        dirty = next;
        requestRender?.();
      }
      if (dirtyAgain) {
        dirtyAgain = false;
        refreshDirty();
      }
    },
  );
}

let mcpCache: { at: number; health: ReturnType<typeof mcpHealth> } | undefined;
function mcpState() {
  if (mcpCache && Date.now() - mcpCache.at < 1000) return mcpCache.health;
  let connected = new Set<string>();
  try {
    connected = mcpTools?.() ?? connected;
  } catch {
    // tools unavailable while the session is starting
  }
  const health = mcpHealth(connected, reported);
  mcpCache = { at: Date.now(), health };
  return health;
}

function footer(tui: TUI, _theme: unknown, data: { getGitBranch(): string | null; getExtensionStatuses(): ReadonlyMap<string, string>; onBranchChange(cb: () => void): () => void }) {
  statusData = data;
  const request = () => tui.requestRender();
  requestRender = request;
  refreshDirty();
  const unsubscribe = data.onBranchChange(() => {
    refreshDirty();
    tui.requestRender();
  });
  return {
    invalidate() {},
    dispose() {
      unsubscribe();
      if (requestRender === request) requestRender = undefined;
    },
    render(width: number): string[] {
      const ctx = current;
      const t = theme();
      if (!ctx || !t) return [];
      const branch = data.getGitBranch();
      const changed = branch && dirty ? " " + t.fg("muted", `±${dirty}`) : "";
      const elapsed = Math.max(0, Date.now() - runStartedAt);
      const frame = t.fg("borderAccent", activityFill(activityStep));
      let left = waitingQuestions.size
        ? " " + t.fg("warning", "●") + " " + t.fg("muted", "Waiting for your answer")
        : running
          ? " " + frame + " " + t.fg("muted", activity + " · " + formatDuration(elapsed)) + t.fg("dim", " · ") + t.fg("text", "esc") + t.fg("muted", " interrupt")
        : " " + t.fg("muted", shortenPath(ctx.cwd, undefined, process.env.HOME)) + (branch ? t.fg("dim", " · ") + t.fg("muted", branch) + changed : "");
      const { rest } = footerStatuses(data.getExtensionStatuses());
      const parts: string[] = [];
      const mcp = mcpState();
      const mark = (token: "success" | "error" | "warning", count: number, label: string) => t.fg(token, "●") + t.fg("muted", ` ${count} ${label}`);
      const servers = [
        mcp.connected ? mark("success", mcp.connected, "connected") : "",
        mcp.signin ? mark("warning", mcp.signin, "sign in") : "",
        mcp.errors ? mark("error", mcp.errors, mcp.errors === 1 ? "error" : "errors") : "",
      ].filter(Boolean);
      if (servers.length) parts.push(servers.join("  "));
      const usage = ctx.getContextUsage();
      if (usage?.tokens != null) {
        const pct = usage.percent ?? 0;
        const shade = pct > 90 ? "error" : pct > 70 ? "warning" : "muted";
        parts.push(t.fg(shade, `${formatTokens(usage.tokens)} (${Math.round(pct)}%)`));
      }
      const cost = sessionCost(ctx);
      if (cost > 0) parts.push(t.fg("muted", `$${cost.toFixed(2)}`));
      for (const status of rest) parts.push(t.fg("muted", stripAnsi(status)));
      parts.push(t.fg("text", "shift+tab") + t.fg("muted", " agents"), t.fg("text", "/") + t.fg("muted", " commands"));
      const join = (items: string[]) => (items.length ? items.join(t.fg("dim", "  ·  ")) + " " : "");
      // Keep MCP attention ahead of a verbose activity; optional hints and other statuses give way first.
      const room = width - visibleWidth(join(parts.slice(0, 1))) - 2;
      if (running && room >= 8) left = truncateToWidth(left, room, "…");
      while (parts.length > 1 && visibleWidth(left) + 3 + visibleWidth(join(parts)) > width) parts.pop();
      return [spread(left, join(parts), width)];
    },
  };
}

// ---------------------------------------------------------------------------------------------------------
// Header

function compactHeader(t: Theme, width: number): string[] {
  const key = (name: string, label: string) => t.fg("text", name) + t.fg("dim", " " + label);
  const hints = [key("esc", "interrupt"), key("/", "commands"), key("!", "shell"), key("ctrl+o", "expand"), key("ctrl+c", "clear")].join(t.fg("dim", "  ·  "));
  return [
    "",
    " ".repeat(TEXT_COLUMN) + t.fg("accent", t.bold("π")) + "  " + t.bold(t.fg("text", "pi")) + " " + t.fg("dim", `v${VERSION}`),
    truncateToWidth(" ".repeat(TEXT_COLUMN) + hints, width, "…"),
    "",
  ];
}

function splashNotifications(t: Theme, width: number): string[] {
  const boxes = toasts.flatMap((body, n) => {
    const color = toastLevels[n] === "error" ? "error" : "warning";
    return [...toastBox({ title: toastLevels[n] === "error" ? "Error" : "Warning", color: (s) => t.fg(color, s), body }, Math.min(46, Math.floor(width / 2)), (s) => t.fg("dim", s)), ""];
  });
  if (boxes.at(-1) === "") boxes.pop();
  return overlayRight(Array(boxes.length).fill(""), boxes, width);
}

function header(tui: TUI) {
  requestHeader = () => tui.requestRender();
  return {
    invalidate() {},
    dispose() {
      requestHeader = undefined;
    },
    render(width: number): string[] {
      const t = theme();
      if (!t) return [];
      return splashEnabled(width, tui.terminal.rows) ? splashNotifications(t, width) : compactHeader(t, width);
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

/** What each finished answer changed on disk, cached per session length like the model switches. */
let changesCache: { count: number; sessionId: string; leaf: string; map: Map<number, TurnChanges> } | undefined;
function turnSummaries(ctx: ExtensionContext): Map<number, TurnChanges> {
  const manager = ctx.sessionManager as any;
  if (!manager) return new Map();
  const count = manager.getEntryCount?.() ?? -1;
  const sessionId = manager.getSessionId?.() ?? "";
  // Navigating the tree moves the leaf without changing the entry count, and the summaries belong to the branch.
  const leaf = manager.getLeafId?.() ?? "";
  if (changesCache && changesCache.count === count && changesCache.sessionId === sessionId && changesCache.leaf === leaf) return changesCache.map;
  const map = turnChanges((manager.getBranch?.() ?? manager.getEntries()) as any[]);
  changesCache = { count, sessionId, leaf, map };
  return map;
}

function answerFooter(component: any, t: Theme, width: number): string[] {
  const message = component.lastMessage;
  if (!message || component.isStreaming || component.hasToolCalls) return [];
  if (!["stop", "length", "aborted", "error"].includes(message.stopReason)) return [];
  const name = current?.modelRegistry?.find?.(message.provider, message.model)?.name ?? message.model;
  const took = durations.get(message.timestamp);
  const end = message.stopReason === "aborted" ? "interrupted" : message.stopReason === "error" ? "failed" : "";
  const from = current ? modelSwitches(current).get(message.timestamp) : undefined;
  const changes = current ? turnSummaries(current).get(message.timestamp) : undefined;
  const detail = [
    ...[name, took !== undefined ? formatDuration(took) : "", end].filter(Boolean).map((part) => t.fg("muted", part)),
    from ? t.fg("warning", `switched from ${from}`) : "",
    changes ? formatChanges(changes, t) : "",
  ]
    .filter(Boolean)
    .join(t.fg("dim", " · "));
  return ["", truncateToWidth(" ".repeat(TEXT_COLUMN) + t.fg("borderAccent", "▣") + "  " + detail, Math.max(1, width), "…")];
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
      const lines = original.call(this, width - 2);
      return memoized(this, `${width}|${panelBg(t)}|${barFg(t)}`, lines, () => lines.map((line) => userBar(line, t)));
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
      const source = original.call(this, width - (TEXT_COLUMN - 1));
      const bg = t.getBgAnsi("toolSuccessBg");
      const fenced = memoized(this, `${width}|${bg}`, source, () => restyleFences(indent(source, TEXT_COLUMN - 1), width, bg, (lang) => t.fg("dim", lang)));
      return [...fenced, ...answerFooter(this, t, width)];
    });
}

// ---------------------------------------------------------------------------------------------------------
// Tools

// A renderer that throws must not take the transcript down, and must not vanish silently either.
class Rows {
  private last?: { width: number; key: string; lines: string[] };
  /**
   * `key`, when given, fingerprints everything `build` reads besides the width. Pi repaints the whole transcript on every
   * frame (a spinner alone does it ten times a second), so an unchanged panel returns its last lines instead of
   * being laid out and highlighted again.
   */
  constructor(
    private readonly build: (width: number) => string[],
    private readonly key?: () => string,
  ) {}
  render(width: number): string[] {
    const key = this.key?.();
    if (key !== undefined && this.last && this.last.width === width && this.last.key === key) return this.last.lines;
    try {
      const lines = this.build(width);
      if (key !== undefined) this.last = { width, key, lines };
      return lines;
    } catch (error) {
      const t = theme();
      const message = `render failed: ${error instanceof Error ? error.message : String(error)}`;
      return [truncateToWidth(" ".repeat(TEXT_COLUMN) + (t ? t.fg("error", message) : message), Math.max(1, width), "…")];
    }
  }
  invalidate() {
    this.last = undefined;
  }
}

/** The last result of a wrapper around one of Pi's own components, reused while its input lines are the same lines. */
const memos = new WeakMap<object, { key: string; input: string[]; output: string[] }>();
function memoized(owner: object, key: string, input: string[], compute: () => string[]): string[] {
  const hit = memos.get(owner);
  if (hit && hit.key === key && hit.input.length === input.length && hit.input.every((line, n) => line === input[n])) return hit.output;
  const output = compute();
  memos.set(owner, { key, input, output });
  return output;
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
  // The checklist above the prompt shows the list; the call itself stays one line.
  todo: {
    icon: "◈",
    verb: "Todo",
    target: (a) => [text(a?.op), Array.isArray(a?.items) ? plural(a.items.length, "task") : a?.id !== undefined ? `#${a.id}` : ""].filter(Boolean).join(" "),
  },
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

/** The command's lines in colour: shell, with heredoc bodies coloured as the file they are written to. */
function commandColors(command: string, t: Theme): (string | undefined)[] {
  const cached = commandCache.get(command);
  if (cached) return cached;
  const base = t.getFgAnsi("text");
  const colored = highlightCommand(command, (code, language) => highlightCode(code, language), getLanguageFromPath).map((line) => (line === undefined ? line : keepForeground(line, base)));
  if (commandCache.size >= 100) commandCache.delete(commandCache.keys().next().value as string);
  commandCache.set(command, colored);
  return colored;
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
        const fingerprint = () => {
          const state = ctx.state as { output?: string };
          return [text(args?.command), executed.get(ctx.toolCallId) ?? "", state.output ?? "", ctx.isError, ctx.expanded, ctx.isPartial, ctx.durationMs ?? ""].join("\u0000");
        };
        return new Rows((width) => {
          const state = ctx.state as { output?: string; failed?: string; pending?: boolean };
          const split = splitShellFailure(state.output ?? "");
          const command = text(args?.command);
          const ran = executed.get(ctx.toolCallId);
          return shellBlock(
            {
              command,
              ran: ran && ran !== command ? ran : undefined,
              output: split.output,
              failure: ctx.isError ? split.failure ?? (split.output ? undefined : "failed") : undefined,
              expanded: ctx.expanded,
              maxLines: 10,
              pending: ctx.isPartial,
              duration: ctx.durationMs,
              hint: hint(),
            },
            width,
            { bg: t.getBgAnsi(ctx.isPartial ? "toolPendingBg" : "toolSuccessBg"), fg: (token, value) => t.fg(token, value), command: (value) => commandColors(value, t) },
          );
        }, fingerprint);
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
        // Highlight once per result: the diff never changes, only the width it is laid out in.
        const lang = getLanguageFromPath(pathOf(ctx.args ?? {}));
        const highlighted = new Map<number, (string | undefined)[]>();
        const code = lang
          ? (shown: ReturnType<typeof parseDiff>) => {
              let colored = highlighted.get(shown.length);
              if (!colored) {
                try {
                  // The highlighter leaves unclassified text in the terminal's default colour; the theme's text colour
                  // is reopened after every reset so no character falls back to it.
                  const base = t.getFgAnsi("text");
                  colored = highlightDiffRows(shown, (source) => highlightCode(source, lang)).map((line) => (line === undefined ? line : keepForeground(line, base)));
                } catch {
                  colored = [];
                }
                highlighted.set(shown.length, colored);
              }
              return colored;
            }
          : undefined;
        return new Rows((width) => {
          const style = {
            fg: (token: any, value: string) => t.fg(token, value),
            bgs: { ctx: t.getBgAnsi("toolSuccessBg"), add: tint(t, "toolDiffAdded", 0.16), del: tint(t, "toolDiffRemoved", 0.18) },
            code,
          };
          const block = diffBlock(rows, width - 2, style, options.expanded ? 400 : 18);
          const hidden = rows.length - 18;
          const more = !options.expanded && hidden > 0 ? [" ".repeat(TEXT_COLUMN) + t.fg("dim", `… ${hidden} more diff lines · ${hint()}`)] : [];
          const notes = warnings.map((line) => " ".repeat(TEXT_COLUMN) + t.fg("warning", truncateToWidth(line, width - TEXT_COLUMN, "…")));
          return [...indent(block, 2), ...more, ...notes];
        }, () => `${options.expanded}|${t.getBgAnsi("toolSuccessBg")}`);
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

  // This instance's own TUI session. Only a TUI session has a working row to drive; an in-process session that loads
  // this extension headless must not take the parent's row over, and an event after the session ended must not touch it.
  let mine: ExtensionContext | undefined;
  let restoreNotify: (() => void) | undefined;
  const endSplash = () => {
    if (!splash) return;
    splash = false;
    toasts = [];
    toastLevels = [];
    requestHeader?.();
  };

  pi.on("session_start", (_event, ctx) => {
    if (ctx.mode !== "tui") return;
    mine = ctx;
    stopTicker();
    running = false;
    waitingQuestions.clear();
    ctx.ui.setWorkingVisible(false);
    const entries = ((ctx.sessionManager as any)?.getEntries?.() ?? []) as any[];
    splash = !entries.some((entry) => entry.type === "message");
    toasts = [];
    toastLevels = [];
    reported.clear();
    mcpCache = undefined;
    mcpTools = () => {
      const servers = new Set<string>();
      for (const tool of pi.getAllTools()) {
        const namespace = tool.namespace;
        if (tool.exposure !== "hidden" && namespace?.name?.startsWith("mcp__")) servers.add(namespace.aliases?.[0] ?? namespace.name);
      }
      return servers;
    };
    // Pi has no event for MCP state; the startup report goes through `notify`, so the shared UI context is wrapped.
    restoreNotify?.();
    const ui = ctx.ui as any;
    const original = ui.notify;
    const wrapped = function (this: unknown, message: string, type?: string) {
      try {
        for (const [name, problem] of parseMcpAttention(String(message))) reported.set(name, problem);
        mcpCache = undefined;
        if (splash && (type === "warning" || type === "error")) {
          toasts.push(String(message).split("\n"));
          toastLevels.push(type);
          toasts.splice(0, Math.max(0, toasts.length - 3));
          toastLevels.splice(0, Math.max(0, toastLevels.length - 3));
        }
        requestHeader?.();
        requestRender?.();
      } catch {
        // a display problem must not swallow the notification
      }
      if (splash && (type === "warning" || type === "error")) return;
      return original.call(this, message, type);
    };
    ui.notify = wrapped;
    restoreNotify = () => {
      if (ui.notify === wrapped) ui.notify = original;
      restoreNotify = undefined;
    };

    commandCache.clear(); // a reload may have changed the theme the cached colours were made with
    owners.set(owner, ctx);
    current = ctx;
    install();
    ctx.ui.setEditorComponent((tui, editorTheme, keybindings) => new PanelEditor(tui, editorTheme, keybindings));
    ctx.ui.setFooter(footer as any);
    ctx.ui.setHeader(header as any);
  });
  let ticker: ReturnType<typeof setInterval> | undefined;
  const showActivity = () => {
    try {
      requestRender?.();
    } catch {
      // The footer can retire between a queued timer and its callback.
    }
  };
  const advanceActivity = () => {
    activityStep = (activityStep + 1) % 64;
    showActivity();
  };
  const setActivity = (next: string) => {
    activity = next;
    showActivity();
  };
  const stopTicker = () => {
    if (ticker) clearInterval(ticker);
    ticker = undefined;
  };

  pi.on("input", () => {
    if (mine) endSplash();
  });
  pi.on("agent_start", () => {
    if (!mine) return;
    endSplash();
    running = true;
    waitingQuestions.clear();
    runStartedAt = Date.now();
    activityStep = 0;
    stopTicker();
    setActivity("Working");
    ticker = setInterval(advanceActivity, 60);
    ticker.unref?.();
  });
  pi.on("agent_end", () => {
    if (!mine) return;
    running = false;
    waitingQuestions.clear();
    stopTicker();
    showActivity();
    refreshDirty();
  });
  pi.on("tool_execution_start", (event) => {
    if (!mine || event.parentToolCallId || !running) return;
    if (event.toolName === "question") {
      waitingQuestions.add(event.toolCallId);
      stopTicker();
      showActivity();
    } else if (!waitingQuestions.size) setActivity(describeActivity(event.toolName, event.args, mine.cwd, process.env.HOME));
  });
  pi.on("tool_execution_end", (event) => {
    if (!mine || event.parentToolCallId) return;
    if (event.toolName === "question") {
      waitingQuestions.delete(event.toolCallId);
      if (running && !waitingQuestions.size && !ticker) {
        ticker = setInterval(advanceActivity, 60);
        ticker.unref?.();
      }
    }
    if (running && !waitingQuestions.size) setActivity("Working");
    // A file-changing tool may have touched the tree; reads and searches cannot.
    if (!["read", "ls", "grep", "find", "question"].includes(event.toolName)) refreshDirty();
  });
  pi.on("tool_result", (event) => {
    const command = (event as any).input?.command;
    if (event.toolName !== "bash" || typeof command !== "string") return;
    executed.set(event.toolCallId, command);
    if (executed.size > 300) executed.delete(executed.keys().next().value as string);
  });
  pi.on("message_end", (event) => {
    const message = event.message as any;
    if (mine && message?.role === "assistant" && runStartedAt) durations.set(message.timestamp, Date.now() - runStartedAt);
  });
  pi.on("session_shutdown", () => {
    // The timer and the context go first, whether or not this instance owned a TUI.
    stopTicker();
    restoreNotify?.();
    if (mine) {
      running = false;
      waitingQuestions.clear();
      try { mine.ui.setWorkingVisible(true); } catch {}
    }
    mine = undefined;
    if (!owners.delete(owner)) return;
    current = [...owners.values()].at(-1);
    if (owners.size) return;
    for (const { prototype, original, wrapped } of patches) if (prototype.render === wrapped) prototype.render = original;
    patches.length = 0;
    durations.clear();
    executed.clear();
    commandCache.clear();
    switchCache = undefined;
    changesCache = undefined;
    costCache = undefined;
    dirty = undefined;
    mcpTools = undefined;
    statusData = undefined;
    requestHeader = undefined;
    reported.clear();
    toasts = [];
    toastLevels = [];
  });
}
