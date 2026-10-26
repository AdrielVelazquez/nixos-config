// Pure rendering helpers for the OpenCode-style Pi skin. No Pi runtime state lives here, so every
// function can be exercised from a plain node test with only pi-tui's width helpers.
import { truncateToWidth, visibleWidth, wrapTextWithAnsi } from "@earendil-works/pi-tui";

const SGR = /\x1b\[([0-9;]*)m/g;
const ANSI = /\x1b\[[0-9;]*m|\x1b\][^\x07]*\x07|\x1b_[^\x07]*\x07/g;
export const RESET_BG = "\x1b[49m";

export const stripAnsi = (text: string): string => text.replace(ANSI, "");

/** True when an SGR sequence leaves the background unset: a full reset or `49`, not followed by a new background. */
function clearsBackground(body: string): boolean {
  const codes = body === "" ? [0] : body.split(";").map(Number);
  let cleared = false;
  for (let i = 0; i < codes.length; i++) {
    const code = codes[i];
    if (code === 0 || code === 49) cleared = true;
    else if ((code >= 40 && code <= 47) || (code >= 100 && code <= 107)) cleared = false;
    else if (code === 38 || code === 48) {
      if (code === 48) cleared = false;
      i += codes[i + 1] === 2 ? 4 : codes[i + 1] === 5 ? 2 : 0;
    }
  }
  return cleared;
}

/** Re-open a background after every sequence that closes it, so a fill survives nested styling. */
export function keepBackground(line: string, bgOpen: string): string {
  return line.replace(SGR, (sequence, body: string) => (clearsBackground(body) ? sequence + bgOpen : sequence));
}

/** True when an SGR sequence leaves the foreground unset: a full reset or `39`, not followed by a new foreground. */
function clearsForeground(body: string): boolean {
  const codes = body === "" ? [0] : body.split(";").map(Number);
  let cleared = false;
  for (let i = 0; i < codes.length; i++) {
    const code = codes[i];
    if (code === 0 || code === 39) cleared = true;
    else if ((code >= 30 && code <= 37) || (code >= 90 && code <= 97)) cleared = false;
    else if (code === 38 || code === 48) {
      if (code === 38) cleared = false;
      i += codes[i + 1] === 2 ? 4 : codes[i + 1] === 5 ? 2 : 0;
    }
  }
  return cleared;
}

/**
 * Open `fgOpen` before a line and re-open it after every sequence that closes the foreground, so text a highlighter
 * left uncoloured takes the theme's text colour instead of the terminal's own default.
 */
export function keepForeground(line: string, fgOpen: string): string {
  return fgOpen + line.replace(SGR, (sequence, body: string) => (clearsForeground(body) ? sequence + fgOpen : sequence));
}

/** Fill a line to `width` columns with a background, truncating anything wider. */
export function paint(line: string, width: number, bgOpen: string): string {
  if (width <= 0) return "";
  const fitted = visibleWidth(line) > width ? truncateToWidth(line, width, "") : line;
  const pad = Math.max(0, width - visibleWidth(fitted));
  return bgOpen + keepBackground(fitted, bgOpen) + " ".repeat(pad) + RESET_BG;
}

/** Indent every non-empty line. Empty lines stay empty so spacing rows keep no stray cells. */
export function indent(lines: string[], columns: number): string[] {
  const pad = " ".repeat(columns);
  return lines.map((line) => (line === "" ? line : pad + line));
}

export function formatDuration(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return "";
  if (ms < 1000) return `${Math.round(ms)}ms`;
  const seconds = ms / 1000;
  if (seconds < 60) return `${seconds < 10 ? seconds.toFixed(1) : Math.round(seconds)}s`;
  const minutes = Math.floor(seconds / 60);
  const rest = Math.round(seconds % 60);
  return minutes < 60 ? `${minutes}m ${rest}s` : `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}

export function formatTokens(count: number): string {
  if (count < 1000) return String(Math.round(count));
  if (count < 10000) return `${(count / 1000).toFixed(1)}K`;
  if (count < 1000000) return `${Math.round(count / 1000)}K`;
  return `${(count / 1000000).toFixed(1)}M`;
}

export function shortenPath(path: string, cwd?: string, home?: string): string {
  if (!path) return path;
  if (cwd && path.startsWith(cwd + "/")) return path.slice(cwd.length + 1);
  if (home && path === home) return "~";
  if (home && path.startsWith(home + "/")) return "~" + path.slice(home.length);
  return path;
}

/** `left` and `right` on one row of `width` columns; the right side is dropped before the left is cut. */
export function spread(left: string, right: string, width: number): string {
  const rightWidth = visibleWidth(right);
  const room = width - rightWidth - 2;
  if (rightWidth && room >= 8) {
    const shown = truncateToWidth(left, room, "…");
    return shown + " ".repeat(Math.max(1, width - visibleWidth(shown) - rightWidth)) + right;
  }
  return truncateToWidth(left, width, "…");
}

export interface DiffRow {
  kind: "add" | "del" | "ctx" | "gap";
  no: string;
  text: string;
}

/** Parse Pi's `generateDiffString` output: `+12 text`, `-12 text`, ` 12 text` and ` ... ` gaps. */
export function parseDiff(diff: string): DiffRow[] {
  const rows: DiffRow[] = [];
  for (const line of diff.split("\n")) {
    if (line === "") continue;
    const match = /^([+\- ])\s*(\d*) ?(.*)$/.exec(line);
    if (!match) continue;
    const [, sign, no, text] = match;
    if (sign === " " && no === "" && text.trim() === "...") rows.push({ kind: "gap", no: "", text: "" });
    else rows.push({ kind: sign === "+" ? "add" : sign === "-" ? "del" : "ctx", no, text });
  }
  return rows;
}

export interface DiffStyle {
  fg: (token: "success" | "error" | "dim" | "muted" | "text", text: string) => string;
  bgs: { ctx: string; add: string; del: string };
  /**
   * Syntax-coloured text for each row, aligned with `rows` (see `highlightDiffRows`). A row without an entry is
   * drawn in the plain text colour, so a language the highlighter does not know costs nothing.
   */
  code?: (rows: DiffRow[]) => (string | undefined)[];
}

/**
 * Colour the code of diff rows with `highlight`, which turns code into one coloured line per input line.
 * The old side (context and removed rows) and the new side (context and added rows) are highlighted as separate
 * listings, so multi-line constructs stay intact on each side; a gap in the diff starts a new listing, because
 * the lines it hides may change what a line means. A highlighter that returns a different number of lines is
 * ignored for that listing.
 */
export function highlightDiffRows(rows: DiffRow[], highlight: (code: string) => string[]): (string | undefined)[] {
  const colored: (string | undefined)[] = new Array(rows.length).fill(undefined);
  const apply = (indexes: number[]) => {
    if (indexes.length === 0) return;
    const lines = highlight(indexes.map((index) => rows[index].text.replace(/\t/g, "  ")).join("\n"));
    if (lines.length !== indexes.length) return;
    indexes.forEach((index, n) => {
      colored[index] = lines[n];
    });
  };
  let start = 0;
  for (let end = 0; end <= rows.length; end++) {
    if (end < rows.length && rows[end].kind !== "gap") continue;
    const segment = Array.from({ length: end - start }, (_, n) => start + n);
    apply(segment.filter((index) => rows[index].kind !== "add"));
    // The new side runs last, so context rows take their colours from it.
    apply(segment.filter((index) => rows[index].kind !== "del"));
    start = end + 1;
  }
  return colored;
}

/** A full-width diff block: line-number gutter, sign column and a tinted row for each change. */
export function diffBlock(rows: DiffRow[], width: number, style: DiffStyle, maxRows: number): string[] {
  if (rows.length === 0 || width < 12) return [];
  const gutter = Math.max(...rows.map((row) => row.no.length), 1);
  const shown = rows.length > maxRows ? rows.slice(0, maxRows) : rows;
  const colored = style.code?.(shown) ?? [];
  const body = shown.map((row, index) => {
    if (row.kind === "gap") return paint(style.fg("dim", " ".repeat(gutter + 1) + "⋯"), width, style.bgs.ctx);
    const sign = row.kind === "add" ? style.fg("success", "+") : row.kind === "del" ? style.fg("error", "-") : " ";
    const number = style.fg("dim", row.no.padStart(gutter));
    const bg = style.bgs[row.kind];
    const text = colored[index] ?? style.fg("text", row.text.replace(/\t/g, "  "));
    return paint(` ${number} ${sign} ${text}`, width, bg);
  });
  const blank = paint("", width, style.bgs.ctx);
  return [blank, ...body, blank];
}

export interface BlockStyle {
  bg: string;
  fg: (token: "text" | "muted" | "dim" | "error" | "warning", text: string) => string;
  /** Coloured lines for the command, one per line of it (see `highlightCommand`); a missing entry is drawn plain. */
  command?: (command: string) => (string | undefined)[];
}

export interface ShellBlock {
  command: string;
  /** What actually ran, when a hook rewrote the command (rtk): shown under the command, since nothing else says so. */
  ran?: string;
  output: string;
  expanded: boolean;
  maxLines: number;
  pending: boolean;
  failure?: string;
  duration?: number;
  hint: string;
}

/** Split a failed bash result into its output and the trailing "Command exited..." sentence. */
export function splitShellFailure(text: string): { output: string; failure?: string } {
  const match = /\n*(Command exited with code \d+|Command timed out[^\n]*|Command aborted[^\n]*)\s*$/.exec(text);
  if (!match) return { output: text.trim() };
  const code = /code (\d+)/.exec(match[1]);
  return { output: text.slice(0, match.index).trim(), failure: code ? `exit ${code[1]}` : match[1].trim() };
}

/** The OpenCode bash panel: `$ command`, a gap, then the output tail, all on one filled background. */
export function shellBlock(block: ShellBlock, width: number, style: BlockStyle): string[] {
  if (width < 12) return [];
  const inner = width - 5;
  const row = (text: string) => paint("   " + text, width, style.bg);
  const rows: string[] = [row("")];
  const command = block.command || "…";
  const colored = style.command?.(command) ?? [];
  command.split("\n").forEach((line, n) => {
    const body = colored[n] ?? style.fg("text", line);
    for (const wrapped of wrapTextWithAnsi(n === 0 ? `${style.fg("dim", "$")} ${body}` : body, inner)) rows.push(row(wrapped));
  });
  if (block.ran && block.ran !== block.command) {
    for (const wrapped of wrapTextWithAnsi(style.fg("dim", `↳ ${block.ran.split("\n")[0]}${block.ran.includes("\n") ? " …" : ""}`), inner)) rows.push(row(wrapped));
  }
  const output = block.output.trimEnd();
  if (output) {
    rows.push(row(""));
    const visual: string[] = [];
    for (const line of output.split("\n")) {
      const wrapped = wrapTextWithAnsi(style.fg("muted", line.replace(/\t/g, "  ")), inner);
      visual.push(...(wrapped.length ? wrapped : [""]));
    }
    const hidden = block.expanded ? 0 : Math.max(0, visual.length - block.maxLines);
    if (hidden) rows.push(row(style.fg("dim", `… ${hidden} earlier line${hidden === 1 ? "" : "s"} · ${block.hint}`)));
    for (const line of hidden ? visual.slice(-block.maxLines) : visual) rows.push(row(line));
  }
  const tail = [block.failure ? style.fg("error", block.failure) : "", block.duration && block.duration >= 1000 ? style.fg("dim", formatDuration(block.duration)) : ""]
    .filter(Boolean)
    .join(style.fg("dim", " · "));
  if (tail) rows.push(row(""), row(tail));
  rows.push(row(""));
  return rows;
}

/** Remove up to `count` leading plain spaces, ignoring escape sequences that sit between them. */
export function dropColumns(line: string, count: number): string {
  let out = "";
  let dropped = 0;
  for (let i = 0; i < line.length; ) {
    const sequence = /^\x1b\[[0-9;]*m/.exec(line.slice(i));
    if (sequence) {
      out += sequence[0];
      i += sequence[0].length;
    } else if (dropped < count && line[i] === " ") {
      dropped++;
      i++;
    } else return out + line.slice(i);
  }
  return out;
}

/**
 * Restyle markdown fences from "```ts ... ```" to a filled block with a muted language label.
 * Pi's Markdown prints the fences as visible lines, so they are recognised by their text alone. The
 * fence's own left padding tells how many structural columns precede the code in each block line.
 */
/** pi-tui indents fenced code by two columns after the message padding. */
const CODE_INDENT = 2;

export function restyleFences(lines: string[], width: number, bgOpen: string, label: (lang: string) => string): string[] {
  const out: string[] = [];
  const margin = "  ";
  const inner = Math.max(1, width - margin.length * 2);
  let lead = -1;
  for (const line of lines) {
    const fence = /^( *)```(\S*)\s*$/.exec(stripAnsi(line));
    if (fence && lead < 0) {
      lead = fence[1].length;
      out.push(margin + paint(fence[2] ? " " + label(fence[2]) : "", inner, bgOpen));
    } else if (fence) {
      lead = -1;
      out.push(margin + paint("", inner, bgOpen));
    } else if (lead >= 0) out.push(margin + paint(" " + dropColumns(line, lead + CODE_INDENT), inner, bgOpen));
    else out.push(line);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------
// Turn summary

export interface TurnChanges {
  files: number;
  added: number;
  removed: number;
}

const FINAL_STOPS = ["stop", "length", "aborted", "error"];
const toolCalls = (message: any): { id: string; name: string; args: any }[] =>
  Array.isArray(message?.content)
    ? message.content
        .filter((part: any) => part?.type === "toolCall")
        .map((part: any) => ({ id: String(part.id), name: String(part.name), args: part.arguments ?? {} }))
    : [];

/**
 * The file changes the `edit` and `write` tools made between one final answer and the next, keyed by the timestamp of
 * the answer that closes them. `entries` is a session branch in order. A `write` counts as added lines: the tool does
 * not say how much of an existing file it replaced.
 */
export function turnChanges(entries: readonly any[]): Map<number, TurnChanges> {
  const result = new Map<number, TurnChanges>();
  const calls = new Map<string, { name: string; args: any }>();
  let files = new Set<string>();
  let added = 0;
  let removed = 0;
  for (const entry of entries) {
    const message = entry?.type === "message" ? entry.message : undefined;
    if (!message) continue;
    if (message.role === "assistant") {
      const own = toolCalls(message);
      for (const call of own) calls.set(call.id, call);
      if (own.length === 0 && FINAL_STOPS.includes(message.stopReason)) {
        if (files.size > 0) result.set(message.timestamp, { files: files.size, added, removed });
        files = new Set();
        added = 0;
        removed = 0;
      }
    } else if (message.role === "toolResult" && !message.isError && message.toolName === "bash") {
      // A file written through a heredoc (`cat > f <<'E'`) is a write the edit tools never saw; it counts like one.
      const command = calls.get(String(message.toolCallId))?.args?.command;
      if (typeof command === "string") {
        for (const write of heredocWrites(command)) {
          files.add(write.path);
          added += write.lines;
        }
      }
    } else if (message.role === "toolResult" && !message.isError && (message.toolName === "edit" || message.toolName === "write")) {
      const call = calls.get(String(message.toolCallId));
      const path = call?.args?.path ?? call?.args?.file_path;
      files.add(typeof path === "string" && path ? path : String(message.toolCallId));
      if (message.toolName === "write") {
        const content = call?.args?.content;
        if (typeof content === "string" && content) added += content.split("\n").length - (content.endsWith("\n") ? 1 : 0);
      } else {
        for (const row of parseDiff(typeof message.details?.diff === "string" ? message.details.diff : "")) {
          if (row.kind === "add") added++;
          else if (row.kind === "del") removed++;
        }
      }
    }
  }
  return result;
}

/** `✎ 2 files +12 −3`, the changed-files tail of an answer footer. */
export function formatChanges(
  changes: TurnChanges,
  style: { fg: (token: "muted" | "success" | "error", text: string) => string },
): string {
  const parts = [style.fg("muted", `✎ ${changes.files} file${changes.files === 1 ? "" : "s"}`)];
  if (changes.added) parts.push(style.fg("success", `+${changes.added}`));
  if (changes.removed) parts.push(style.fg("error", `−${changes.removed}`));
  return parts.join(" ");
}

// ---------------------------------------------------------------------------------------------------------
// Live activity

const ACTIVITY_VERBS: Record<string, string> = { read: "Reading", ls: "Listing", grep: "Searching", find: "Searching", write: "Writing", edit: "Editing" };

/** What the agent is doing while a tool runs: `Reading src/auth.ts`, `Running nix build`, or the tool's own name. */
export function describeActivity(toolName: string, args: any, cwd?: string, home?: string): string {
  if (toolName === "bash") {
    const command = typeof args?.command === "string" ? args.command.trim().split("\n")[0] : "";
    return command ? `Running ${command.length > 48 ? `${command.slice(0, 47)}…` : command}` : "Running a command";
  }
  const verb = ACTIVITY_VERBS[toolName];
  if (!verb) return toolName.replace(/^mcp__/, "").replace(/__/g, " ").replace(/_/g, " ");
  const search = toolName === "grep" || toolName === "find";
  const named = search ? args?.pattern : (args?.path ?? args?.file_path);
  const what = typeof named === "string" && named ? (search ? named : shortenPath(named, cwd, home)) : "";
  return what ? `${verb} ${what}` : verb;
}

/** The working message: the activity, and how long it has lasted once that is worth showing. */
export function workingMessage(activity: string, elapsedMs: number): string {
  return elapsedMs >= 3000 ? `${activity} · ${formatDuration(elapsedMs)}` : activity;
}

// ---------------------------------------------------------------------------------------------------------
// Footer statuses

export interface FooterStatuses {
  /** The active role when it is not the default one: a mode worth seeing, not a constant. */
  role?: string;
  rest: string[];
}

/** Statuses that never change during a session and so only take room. */
const CONSTANT_STATUSES = new Set(["ast-grep", "model-role-consumer"]);

/**
 * Turn the extension statuses into what the footer shows. `model-roles` reports `role: plan` or
 * `plan → provider/model • high`; only a role other than `default` is worth a badge, and the model it chose is already
 * in the prompt panel. Statuses of constant capabilities are dropped.
 */
export function footerStatuses(statuses: ReadonlyMap<string, string>): FooterStatuses {
  const out: FooterStatuses = { rest: [] };
  for (const [key, text] of statuses) {
    const clean = text.replace(/[\r\n\t]+/g, " ").trim();
    if (!clean || CONSTANT_STATUSES.has(key)) continue;
    if (key === "model-roles") {
      const role = /^role: (\S+)$/.exec(clean)?.[1] ?? /^(\S+) →/.exec(clean)?.[1];
      if (role && role !== "default" && role !== "auto") out.role = role;
      continue;
    }
    out.rest.push(clean);
  }
  return out;
}

// ---------------------------------------------------------------------------------------------------------
// Shell commands that write files

/** A heredoc in a shell command: `cat > main.go <<'EOF'` followed by its body. */
export interface Heredoc {
  /** The file the body is written to (`> f`, `>> f`, `tee f`), when the line names one. */
  target?: string;
  append: boolean;
  /** The interpreter that reads the body (`python3 - <<'PY'`), when there is no target. */
  interpreter?: string;
  /** The body is lines `start` up to, not including, `end` of the command; the terminator, when there is one, is line `end`. */
  start: number;
  end: number;
}

const HEREDOC = /<<(-?)[ \t]*(?:'([^']*)'|"([^"]*)"|\\?([A-Za-z_][A-Za-z0-9_]*))/g;
const REDIRECT = /(>>?)[ \t]*(?:'([^']*)'|"([^"]*)"|([^\s;&|<>()]+))/;
const TEE = /\btee[ \t]+(?:-[A-Za-z]+[ \t]+)*(?:'([^']*)'|"([^"]*)"|([^\s;&|<>()-][^\s;&|<>()]*))/;
const INTERPRETERS: Record<string, string> = { python: "python", python3: "python", node: "javascript", bash: "bash", sh: "bash", zsh: "bash", ruby: "ruby", perl: "perl", psql: "sql", sqlite3: "sql" };

/** Every heredoc in `command`, in order. A parse that guesses wrong (a `<<` inside a string) only costs some colour. */
export function findHeredocs(command: string): Heredoc[] {
  const lines = command.split("\n");
  const found: Heredoc[] = [];
  let i = 0;
  while (i < lines.length) {
    const line = lines[i];
    let next = i + 1;
    for (const match of line.matchAll(HEREDOC)) {
      const at = match.index ?? 0;
      if (line[at - 1] === "<") continue; // a here-string, `<<<`
      const tag = match[2] ?? match[3] ?? match[4] ?? "";
      // Only the simple command this heredoc belongs to: `cat <<A > a; cat <<B > b` has two, each with its own target.
      const before = line.slice(0, at).split(/[;&|]/).pop() ?? "";
      const after = line.slice(at + match[0].length).split(/[;&|]/)[0];
      const redirect = REDIRECT.exec(before) ?? REDIRECT.exec(after);
      const tee = TEE.exec(before);
      const target = redirect ? (redirect[2] ?? redirect[3] ?? redirect[4]) : tee ? (tee[1] ?? tee[2] ?? tee[3]) : undefined;
      // The last word before the `<<` that names an interpreter (`python3 - <<'PY'`, `ssh host bash <<E`).
      const interpreter = before.trim().split(/\s+/).map((word) => word.split("/").pop() ?? word).filter((word) => word in INTERPRETERS).pop();
      let end = next;
      while (end < lines.length && (match[1] ? lines[end].replace(/^\t+/, "") : lines[end]) !== tag) end++;
      found.push({ target, append: redirect?.[1] === ">>" || (!redirect && !!tee && /\btee[ \t]+-[A-Za-z]*a/.test(before)), interpreter, start: next, end });
      next = end + 1;
    }
    i = next;
  }
  return found;
}

/** The files a command writes through heredocs, with how many lines each body has: what a turn summary can count. */
export function heredocWrites(command: string): { path: string; lines: number }[] {
  return findHeredocs(command)
    .filter((doc) => doc.target && !doc.target.startsWith("/dev/") && !doc.target.includes("$") && !doc.target.startsWith("-"))
    .map((doc) => ({ path: doc.target as string, lines: doc.end - doc.start }));
}

/**
 * Coloured lines for a shell command, one per line of it. A heredoc body is highlighted as the language of the file it
 * is written to (`cat > main.go <<'E'` is Go) or of the interpreter that reads it (`python3 - <<'PY'`), and a body
 * without a known language stays plain; everything else is highlighted as shell, one listing per run of lines so a
 * body cannot confuse it. `highlight` turns code into one coloured line per input line.
 */
export function highlightCommand(
  command: string,
  highlight: (code: string, language: string) => string[],
  languageOf: (path: string) => string | undefined,
): (string | undefined)[] {
  const lines = command.split("\n");
  const colored: (string | undefined)[] = new Array(lines.length).fill(undefined);
  const body = new Array<boolean>(lines.length).fill(false);
  const apply = (from: number, to: number, language: string) => {
    if (to <= from) return;
    try {
      const out = highlight(lines.slice(from, to).join("\n"), language);
      if (out.length === to - from) out.forEach((line, n) => { colored[from + n] = line; });
    } catch {
      // A language the highlighter cannot read stays plain.
    }
  };
  for (const doc of findHeredocs(command)) {
    for (let n = doc.start; n < Math.min(doc.end, lines.length); n++) body[n] = true;
    const language = doc.target ? languageOf(doc.target) : doc.interpreter ? INTERPRETERS[doc.interpreter] : undefined;
    if (language) apply(doc.start, doc.end, language);
  }
  for (let n = 0; n < lines.length; ) {
    if (body[n]) {
      n++;
      continue;
    }
    let end = n;
    while (end < lines.length && !body[end]) end++;
    apply(n, end, "bash");
    n = end;
  }
  return colored;
}

// ---------------------------------------------------------------------------------------------------------
// Agent label, MCP health, splash

/** The name of a role as the prompt panel shows it: the default role is the build agent. */
export function roleLabel(role: string | undefined): string {
  if (!role || role === "default" || role === "auto") return "Build";
  return role.charAt(0).toUpperCase() + role.slice(1);
}

export type McpProblem = "signin" | "error";

/**
 * The servers named by Pi's startup report (`MCP servers need attention:` followed by indented `name: state` lines).
 * Pi keeps connection state private, so the report is the only place a failure is visible to an extension.
 */
export function parseMcpAttention(message: string): Map<string, McpProblem> {
  const found = new Map<string, McpProblem>();
  if (!/^MCP servers need attention:/.test(message)) return found;
  for (const line of message.split("\n").slice(1)) {
    const match = /^\s+(config|[^\s:]+): (.+)$/.exec(line);
    if (!match) continue;
    const [, name, state] = match;
    if (name === "config") found.set(`config: ${state}`, "error");
    else found.set(name, state.startsWith("needs sign-in") ? "signin" : "error");
  }
  return found;
}

export interface McpHealth {
  connected: number;
  errors: number;
  signin: number;
}

/** A server that connected since it was reported is healthy again; the rest keep their reported problem. */
export function mcpHealth(connected: ReadonlySet<string>, reported: ReadonlyMap<string, McpProblem>): McpHealth {
  const health: McpHealth = { connected: connected.size, errors: 0, signin: 0 };
  for (const [name, problem] of reported) {
    if (connected.has(name)) continue;
    if (problem === "signin") health.signin++;
    else health.errors++;
  }
  return health;
}

const LOGO_GLYPHS: Record<string, string[]> = {
  p: ["█▀▀█", "█  █", "█▀▀▀", "█   ", "▀   "],
  i: ["▄", "█", "█", "█", "▀"],
};

/** The wordmark in block letters, one string per row: `parts` are painted in turn, each with its own colour. */
export function logoRows(parts: { text: string; paint: (s: string) => string }[]): string[] {
  const rows = ["", "", "", "", ""];
  for (const part of parts) {
    for (const letter of part.text) {
      const glyph = LOGO_GLYPHS[letter];
      if (!glyph) continue;
      glyph.forEach((row, n) => (rows[n] += part.paint([...row].map((c) => c + c).join("")) + "  "));
    }
  }
  return rows.map((row) => row.replace(/ +$/, ""));
}

/** `lines` centred in `width` columns. */
export function centered(lines: string[], width: number): string[] {
  return lines.map((line) => " ".repeat(Math.max(0, Math.floor((width - visibleWidth(line)) / 2))) + line);
}

export interface Toast {
  title: string;
  /** Colours the frame and the title. */
  color: (s: string) => string;
  body: string[];
}

/** A rounded notification box in the style of Neovim's Noice, `outer` columns wide at most. */
export function toastBox(toast: Toast, outer: number, dim: (s: string) => string): string[] {
  const inner = Math.max(10, outer - 4);
  const body = toast.body.flatMap((line) => (line.trim() ? wrapTextWithAnsi(line, inner) : [""]));
  const width = Math.min(inner, Math.max(visibleWidth(toast.title) + 2, ...body.map((line) => visibleWidth(line))));
  const row = (content: string) => toast.color("│") + " " + content + " ".repeat(Math.max(0, width - visibleWidth(content))) + " " + toast.color("│");
  const head = ` ${toast.title} `;
  const top = toast.color("╭─") + toast.color(head) + toast.color("─".repeat(Math.max(0, width + 1 - visibleWidth(head))) + "╮");
  return [top, ...body.map((line) => row(truncateToWidth(line, width, "…"))), toast.color("╰" + "─".repeat(width + 2) + "╯")];
}

/** Overlays `box` on the right edge of `rows`, starting at row `top`; rows keep their own width. */
export function overlayRight(rows: string[], box: string[], width: number, top = 0, margin = 2): string[] {
  return rows.map((row, n) => {
    const piece = box[n - top];
    if (piece === undefined) return row;
    const left = truncateToWidth(row, Math.max(0, width - visibleWidth(piece) - margin - 1), "");
    return left + " ".repeat(Math.max(1, width - visibleWidth(left) - visibleWidth(piece) - margin)) + piece;
  });
}
