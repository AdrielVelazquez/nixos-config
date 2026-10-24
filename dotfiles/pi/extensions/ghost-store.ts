import { randomUUID } from 'node:crypto';
import { mkdir, open, readFile, rename, stat, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { applyDelta, isEmptyDelta, parseSnapshot, type GhostEngine } from './ghost-core.ts';

/** A lock older than this belongs to a process that died while holding it. */
const STALE_LOCK_MS = 10_000;

function pause(ms: number): Promise<void> {
  const { promise, resolve } = Promise.withResolvers<void>();
  setTimeout(resolve, ms);
  return promise;
}

const code = (error: unknown) => error instanceof Error && 'code' in error ? error.code : undefined;

/** Run `work` holding an exclusive lock file; undefined when the lock stayed busy for `waitMs`. */
export async function withLock<T>(lockPath: string, work: () => Promise<T>, waitMs: number): Promise<T | undefined> {
  const deadline = Date.now() + waitMs;
  for (;;) {
    try {
      const handle = await open(lockPath, 'wx', 0o600);
      await handle.writeFile(`${process.pid} ${Date.now()}`);
      await handle.close();
      break;
    } catch (error) {
      if (code(error) !== 'EEXIST') throw error;
      const age = await stat(lockPath).then(info => Date.now() - info.mtimeMs, () => 0);
      if (age > STALE_LOCK_MS) { await unlink(lockPath).catch(() => {}); continue; }
      if (Date.now() >= deadline) return undefined;
      await pause(15 + Math.random() * 30);
    }
  }
  try { return await work(); } finally { await unlink(lockPath).catch(() => {}); }
}

export const statePathOf = (dir: string) => join(dir, 'ghost-text-state.json');

/** Run `work` under the state directory's lock, creating the private directory first. */
export async function withStateLock<T>(dir: string, work: () => Promise<T>, waitMs = 3000): Promise<T | undefined> {
  await mkdir(dir, { recursive: true, mode: 0o700 });
  return withLock(join(dir, 'ghost-text-state.lock'), work, waitMs);
}

/**
 * Merge this session's learning into the shared state file. The caller holds the lock.
 * The file carries a revision: when it still matches the engine's, nobody else saved and the engine
 * already holds everything, so only the delta is merged; otherwise the engine adopts what others saved.
 */
export async function commitLocked(engine: GhostEngine, statePath: string): Promise<void> {
  let disk;
  try { disk = parseSnapshot(JSON.parse(await readFile(statePath, 'utf8'))); }
  catch { /* missing or unreadable: what this session knows becomes the state */ }
  const taken = engine.takeDelta();
  const foreign = disk !== undefined && disk.rev !== engine.revision;
  if (disk && isEmptyDelta(taken)) {
    if (foreign) { engine.revision = disk.rev; engine.rebase(disk); }
    return;
  }
  const merged = disk ? applyDelta(disk, taken) : engine.copyState();
  merged.rev = (disk?.rev ?? engine.revision) + 1;
  const temp = statePath + '.' + randomUUID() + '.tmp';
  try {
    await writeFile(temp, JSON.stringify(merged), { mode: 0o600, flag: 'wx' });
    await rename(temp, statePath);
  } catch (error) {
    engine.restoreDelta(taken);
    throw error;
  } finally { await unlink(temp).catch(() => {}); }
  engine.revision = merged.rev;
  if (foreign) engine.rebase(merged);
}

/** Commit under the lock; false when another session held it for the whole wait (the learning is kept for the next commit). */
export async function commitState(engine: GhostEngine, dir: string, waitMs = 3000): Promise<boolean> {
  return await withStateLock(dir, async () => { await commitLocked(engine, statePathOf(dir)); return true; }, waitMs) ?? false;
}
