import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { homedir } from 'node:os';
import { dirname, isAbsolute, join, relative, resolve, sep, extname } from 'node:path';

/** One formatter, rendered by Nix: absolute executable, fixed arguments, owned extensions. */
export type FormatterSpec = {
  name: string;
  command: string;
  args: string[];
  extensions: string[];
  rootMarkers: string[];
  requireRootMarker: boolean;
};

export type RunOptions = { absPath: string; input: string; timeoutMs: number; maxOutputBytes: number; root?: string };
export type RunResult = { ok: true; output: string } | { ok: false; reason: string; missing?: boolean };
export type Diff = { added: number; removed: number; text: string };

/** Resolve a tool `path` argument the way Pi's own file tools do. */
export function resolveToolPath(input: string, cwd: string): string {
  let path = input.startsWith('@') ? input.slice(1) : input;
  if (path === '~') path = homedir();
  else if (path.startsWith('~/')) path = join(homedir(), path.slice(2));
  return resolve(cwd, path);
}

/** True when `path` is strictly below `root`, after normalising `..` segments. */
export function isInside(root: string, path: string): boolean {
  const rel = relative(resolve(root), resolve(path));
  return rel !== '' && rel !== '..' && !rel.startsWith(`..${sep}`) && !isAbsolute(rel);
}

function hasMarker(spec: FormatterSpec, absPath: string, root: string): boolean {
  for (let dir = dirname(absPath); ; dir = dirname(dir)) {
    if (spec.rootMarkers.some(marker => existsSync(join(dir, marker)))) return true;
    if (dir === root || dirname(dir) === dir) return false;
  }
}

/** First declared formatter owning the file's extension; gated ones also need a project marker inside `root`. */
export function selectFormatter(formatters: FormatterSpec[], absPath: string, root: string): FormatterSpec | undefined {
  const extension = extname(absPath).toLowerCase();
  if (!extension) return undefined;
  return formatters.find(spec =>
    spec.extensions.some(candidate => candidate.toLowerCase() === extension)
    && (!spec.requireRootMarker || hasMarker(spec, absPath, root)));
}

/** Edition for `rustfmt --edition`: nearest manifest, following workspace inheritance; cargo's 2015 when a package omits it. */
export function cargoEdition(absPath: string, root: string): string {
  for (let dir = dirname(absPath); ; dir = dirname(dir)) {
    const manifest = join(dir, 'Cargo.toml');
    if (existsSync(manifest)) {
      const text = readFileSync(manifest, 'utf8');
      const declared = /^\s*edition\s*=\s*"(\d{4})"/m.exec(text);
      if (declared) return declared[1];
      const inherited = /^\s*edition\.workspace\s*=\s*true|^\s*edition\s*=\s*\{\s*workspace\s*=\s*true/m.test(text);
      if (!inherited && /^\[package\]/m.test(text)) return '2015';
    }
    if (dir === root || dirname(dir) === dir) return '2021';
  }
}

const MAX_COMPARE_CELLS = 4_000_000;

function splitLines(text: string): string[] {
  if (text === '') return [];
  return (text.endsWith('\n') ? text.slice(0, -1) : text).split('\n');
}

/** Compact unified diff of a formatter's change; counts are exact unless the middle is too large to compare. */
export function lineDiff(before: string, after: string, { context = 3, maxLines = 60 } = {}): Diff | undefined {
  if (before === after) return undefined;
  const a = splitLines(before);
  const b = splitLines(after);
  if (a.length === b.length && a.every((line, index) => line === b[index])) {
    return { added: 0, removed: 0, text: after.endsWith('\n') ? '(final newline added)' : '(final newline removed)' };
  }
  let head = 0;
  while (head < a.length && head < b.length && a[head] === b[head]) head++;
  let tail = 0;
  while (tail < a.length - head && tail < b.length - head && a[a.length - 1 - tail] === b[b.length - 1 - tail]) tail++;
  const n = a.length - head - tail;
  const m = b.length - head - tail;
  if (n * m > MAX_COMPARE_CELLS) return { added: m, removed: n, text: '(diff omitted: too large to compare)' };

  const width = m + 1;
  const lcs = new Uint32Array((n + 1) * width);
  for (let i = n - 1; i >= 0; i--) {
    for (let j = m - 1; j >= 0; j--) {
      lcs[i * width + j] = a[head + i] === b[head + j]
        ? lcs[(i + 1) * width + j + 1] + 1
        : Math.max(lcs[(i + 1) * width + j], lcs[i * width + j + 1]);
    }
  }
  type Op = { kind: ' ' | '-' | '+'; line: string };
  const ops: Op[] = [];
  for (let i = 0; i < head; i++) ops.push({ kind: ' ', line: a[i] });
  let i = 0;
  let j = 0;
  while (i < n || j < m) {
    if (i < n && j < m && a[head + i] === b[head + j]) { ops.push({ kind: ' ', line: a[head + i] }); i++; j++; }
    else if (j >= m || (i < n && lcs[(i + 1) * width + j] >= lcs[i * width + j + 1])) { ops.push({ kind: '-', line: a[head + i] }); i++; }
    else { ops.push({ kind: '+', line: b[head + j] }); j++; }
  }
  for (let k = a.length - tail; k < a.length; k++) ops.push({ kind: ' ', line: a[k] });

  const changed = ops.flatMap((op, index) => (op.kind === ' ' ? [] : [index]));
  const oldAt: number[] = [];
  const newAt: number[] = [];
  let oldLine = 1;
  let newLine = 1;
  for (const op of ops) {
    oldAt.push(oldLine);
    newAt.push(newLine);
    if (op.kind !== '+') oldLine++;
    if (op.kind !== '-') newLine++;
  }
  const rows: string[] = [];
  for (let start = 0; start < changed.length;) {
    let end = start;
    while (end + 1 < changed.length && changed[end + 1] - changed[end] <= 2 * context + 1) end++;
    const from = Math.max(0, changed[start] - context);
    const to = Math.min(ops.length - 1, changed[end] + context);
    const slice = ops.slice(from, to + 1);
    const oldCount = slice.filter(op => op.kind !== '+').length;
    const newCount = slice.filter(op => op.kind !== '-').length;
    const oldStart = oldCount === 0 ? oldAt[from] - 1 : oldAt[from];
    const newStart = newCount === 0 ? newAt[from] - 1 : newAt[from];
    rows.push(`@@ -${oldStart},${oldCount} +${newStart},${newCount} @@`, ...slice.map(op => `${op.kind}${op.line}`));
    start = end + 1;
  }
  const kept = rows.length > maxLines ? [...rows.slice(0, maxLines), `… ${rows.length - maxLines} more diff lines`] : rows;
  return {
    added: ops.filter(op => op.kind === '+').length,
    removed: ops.filter(op => op.kind === '-').length,
    text: kept.join('\n'),
  };
}

/** Run one formatter over `input` on stdin; its stdout is the formatted file. Never rejects. */
export function runFormatter(spec: FormatterSpec, { absPath, input, timeoutMs, maxOutputBytes, root }: RunOptions): Promise<RunResult> {
  const { promise, resolve } = Promise.withResolvers<RunResult>();
  let timer: NodeJS.Timeout | undefined;
  let finished = false;
  const finish = (result: RunResult) => {
    if (finished) return;
    finished = true;
    clearTimeout(timer);
    resolve(result);
  };
  let args: string[];
  try {
    args = spec.args.map(arg => arg
      .replaceAll('{file}', absPath)
      .replaceAll('{cargoEdition}', arg.includes('{cargoEdition}') ? cargoEdition(absPath, root ?? dirname(absPath)) : ''));
  } catch (error) {
    finish({ ok: false, reason: error instanceof Error ? error.message : String(error) });
    return promise;
  }
  const child = spawn(spec.command, args, { cwd: dirname(absPath), stdio: ['pipe', 'pipe', 'pipe'] });
  const out: Buffer[] = [];
  let size = 0;
  let stderr = '';
  timer = setTimeout(() => {
    child.kill('SIGKILL');
    finish({ ok: false, reason: `timed out after ${timeoutMs} ms` });
  }, timeoutMs);
  child.on('error', (error: NodeJS.ErrnoException) => {
    finish({ ok: false, reason: `cannot run ${spec.command}: ${error.code ?? error.message}`, missing: error.code === 'ENOENT' });
  });
  child.stdout.on('data', (chunk: Buffer) => {
    size += chunk.length;
    if (size > maxOutputBytes) {
      child.kill('SIGKILL');
      finish({ ok: false, reason: `output exceeded ${maxOutputBytes} bytes` });
      return;
    }
    out.push(chunk);
  });
  child.stderr.on('data', (chunk: Buffer) => { if (stderr.length < 4096) stderr += chunk.toString('utf8'); });
  child.stdin.on('error', () => {});
  child.on('close', (code, signal) => {
    if (code !== 0) {
      const detail = stderr.split('\n').map(line => line.trim()).find(Boolean);
      finish({ ok: false, reason: code === null ? `killed by ${signal}` : `exit ${code}${detail ? `: ${detail}` : ''}` });
      return;
    }
    try {
      finish({ ok: true, output: new TextDecoder('utf-8', { fatal: true }).decode(Buffer.concat(out)) });
    } catch {
      finish({ ok: false, reason: 'output is not valid UTF-8' });
    }
  });
  child.stdin.end(input);
  return promise;
}
