import { execFile } from 'node:child_process';
import { lstat } from 'node:fs/promises';
import { relative, resolve } from 'node:path';

/** Every path git lists as changed or untracked, stamped with its mtime and size: what a command may have touched. */
export type Fingerprint = Map<string, string>;

/** A tree with more dirty paths than this is not worth stamping on every command. */
const MAX_PATHS = 4000;
/** Paths a command writes without anyone wanting them formatted or listed. */
const NOISE = /(^|\/)(node_modules|vendor|\.git|__pycache__)\//;

const tops = new Map<string, string>();

function git(args: string[], cwd: string, timeoutMs: number): Promise<string | undefined> {
  return new Promise((done) => {
    // GIT_OPTIONAL_LOCKS keeps `status` from refreshing the index, which would race the user's own git commands.
    execFile('git', args, { cwd, timeout: timeoutMs, maxBuffer: 16 * 1024 * 1024, env: { ...process.env, GIT_OPTIONAL_LOCKS: '0' } }, (error, stdout) => done(error ? undefined : stdout));
  });
}

/**
 * The state of the working tree as git sees it, or undefined outside a repository, in a tree too large to stamp, or
 * when git does not answer within `timeoutMs`. Stamping before and after a command, then comparing, names the files it
 * wrote without parsing the command.
 */
export async function fingerprint(cwd: string, timeoutMs = 800): Promise<Fingerprint | undefined> {
  let top = tops.get(cwd);
  if (!top) {
    top = (await git(['rev-parse', '--show-toplevel'], cwd, timeoutMs))?.trim();
    if (!top) return undefined;
    tops.set(cwd, top);
  }
  const status = await git(['status', '--porcelain=v1', '-z', '--untracked-files=all', '--no-renames'], cwd, timeoutMs);
  if (status === undefined) return undefined;
  const paths = status.split('\0').filter((entry) => entry.length > 3).map((entry) => entry.slice(3));
  if (paths.length > MAX_PATHS) return undefined;
  const stamps: Fingerprint = new Map();
  await Promise.all(paths.map(async (path) => {
    const absolute = resolve(top, path);
    const info = await lstat(absolute).catch(() => undefined);
    stamps.set(absolute, info ? `${info.mtimeMs}:${info.size}:${info.isFile()}` : 'gone');
  }));
  return stamps;
}

/** The regular files that are dirty after and were not, or were stamped differently, before. Deleted files and noise are left out. */
export function changedBetween(before: Fingerprint, after: Fingerprint): string[] {
  const changed: string[] = [];
  for (const [path, stamp] of after) {
    if (stamp === 'gone' || !stamp.endsWith(':true') || NOISE.test(path)) continue;
    if (before.get(path) !== stamp) changed.push(path);
  }
  return changed.sort();
}

/** One sentence for the model: which files the command changed, capped so a checkout does not flood the result. */
export function describeChanges(paths: string[], cwd: string, limit = 8): string {
  const names = paths.slice(0, limit).map((path) => relative(cwd, path) || path);
  const more = paths.length > limit ? `, and ${paths.length - limit} more` : '';
  return `This command changed ${paths.length} file${paths.length === 1 ? '' : 's'}: ${names.join(', ')}${more}.`;
}
