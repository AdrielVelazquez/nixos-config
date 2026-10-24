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
}

/** A full-width diff block: line-number gutter, sign column and a tinted row for each change. */
export function diffBlock(rows: DiffRow[], width: number, style: DiffStyle, maxRows: number): string[] {
  if (rows.length === 0 || width < 12) return [];
  const gutter = Math.max(...rows.map((row) => row.no.length), 1);
  const shown = rows.length > maxRows ? rows.slice(0, maxRows) : rows;
  const body = shown.map((row) => {
    if (row.kind === "gap") return paint(style.fg("dim", " ".repeat(gutter + 1) + "⋯"), width, style.bgs.ctx);
    const sign = row.kind === "add" ? style.fg("success", "+") : row.kind === "del" ? style.fg("error", "-") : " ";
    const number = style.fg("dim", row.no.padStart(gutter));
    const bg = style.bgs[row.kind];
    return paint(` ${number} ${sign} ${style.fg("text", row.text.replace(/\t/g, "  "))}`, width, bg);
  });
  const blank = paint("", width, style.bgs.ctx);
  return [blank, ...body, blank];
}

export interface BlockStyle {
  bg: string;
  fg: (token: "text" | "muted" | "dim" | "error" | "warning", text: string) => string;
}

export interface ShellBlock {
  command: string;
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
  for (const line of wrapTextWithAnsi(`${style.fg("dim", "$")} ${style.fg("text", command)}`, inner)) rows.push(row(line));
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
