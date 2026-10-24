import { createHash } from 'node:crypto';
import { open, readdir, stat } from 'node:fs/promises';
import { join } from 'node:path';
import type { GhostEngine } from './ghost-core.ts';

export type SeedOptions = { piSessions: boolean; ompSessions: string | null; shellHistory: string[] };
export type Prompt = { text: string; id: string };

/** Session logs are read in small chunks so the editor never stalls; the shell history window is its most recent megabyte. */
const CHUNK = 1 << 18, SHELL_WINDOW = 1 << 20;
/** Typed sessions are named `<timestamp>_<id>.jsonl`; subagent transcripts and task logs hold agent-written prompts. */
const SESSION_NAME = /^\d{4}-\d{2}-\d{2}T[\d-]+Z_.*\.jsonl$/;
const WRAPPERS: Record<string, true> = { sudo: true, doas: true, env: true, time: true, nohup: true, exec: true, command: true, builtin: true, nice: true };

function nextTurn(): Promise<void> {
  const { promise, resolve } = Promise.withResolvers<void>();
  setImmediate(resolve);
  return promise;
}

/** Typed prompts of a Pi or omp session log. Ids equal the live learner's, so replaying a session never counts a message twice. */
export function promptsFromSession(text: string): Prompt[] {
  const prompts: Prompt[] = [];
  for (const line of text.split('\n')) {
    if (!/"role"\s*:\s*"user"/.test(line)) continue;
    try {
      const entry = JSON.parse(line), message = entry?.type === 'message' ? entry.message : undefined;
      if (message?.role !== 'user') continue;
      const content = message.content;
      const prompt = typeof content === 'string' ? content
        : Array.isArray(content) ? content.filter(part => part?.type === 'text' && typeof part.text === 'string').map(part => part.text).join('\n') : '';
      if (prompt) prompts.push({ text: prompt, id: createHash('sha256').update(JSON.stringify([message.role, message.timestamp, prompt])).digest('hex') });
    } catch { /* a partial or foreign line */ }
  }
  return prompts;
}

/** Command names (letters only, three or more) with how often they were run, from zsh/bash history; arguments are never read. */
export function commandNames(text: string): Map<string, number> {
  const uses = new Map<string, number>();
  for (const raw of text.split('\n')) {
    const line = raw.slice(0, 4096).replace(/^: \d+:\d+;/, '').replace(/'[^']*'|"[^"]*"/g, ' ').trim();
    if (!line || line.startsWith('#')) continue;
    for (const segment of line.split(/[|&;`()${}]+/)) {
      const words = segment.trim().split(/\s+/);
      let at = 0, wrapped = false;
      while (at < words.length && (/^[A-Za-z_][A-Za-z0-9_]*=/.test(words[at]) || Object.hasOwn(WRAPPERS, words[at]) || (wrapped && words[at].startsWith('-')))) { wrapped ||= Object.hasOwn(WRAPPERS, words[at]); at++; }
      const command = words[at]?.replace(/^.*\//, '');
      for (const part of command?.split(/[^A-Za-z]+/) ?? []) if (part.length >= 3) uses.set(part.toLowerCase(), (uses.get(part.toLowerCase()) ?? 0) + 1);
    }
  }
  return uses;
}

async function sessionFiles(directory: string): Promise<string[]> {
  let entries;
  try { entries = await readdir(directory, { withFileTypes: true }); } catch { return []; }
  const files: string[] = [];
  for (const entry of entries) {
    const path = join(directory, entry.name);
    if (entry.isDirectory()) files.push(...await sessionFiles(path));
    else if (entry.isFile() && SESSION_NAME.test(entry.name)) files.push(path);
  }
  return files.sort();
}

/** Learn the prompts appended to a session log since the last run; true when the log advanced. */
async function learnSession(engine: GhostEngine, file: string, aborted: () => boolean): Promise<boolean> {
  let size: number;
  try { size = (await stat(file)).size; } catch { return false; }
  let offset = engine.seeded(file);
  if (size < offset) offset = 0;
  if (size === offset) return false;
  const handle = await open(file, 'r');
  try {
    let position = offset, carry: Buffer = Buffer.alloc(0);
    while (!aborted()) {
      const chunk = Buffer.alloc(CHUNK), { bytesRead } = await handle.read(chunk, 0, CHUNK, position);
      if (bytesRead === 0) break;
      position += bytesRead;
      const data = Buffer.concat([carry, chunk.subarray(0, bytesRead)]), cut = data.lastIndexOf(0x0a) + 1;
      carry = data.subarray(cut); // an unfinished last line waits for the next chunk or run
      for (const { text, id } of promptsFromSession(data.subarray(0, cut).toString('utf8'))) engine.observe(text, id);
      engine.setSeeded(file, position - carry.length);
      await nextTurn(); // keep the editor responsive
    }
  } finally { await handle.close(); }
  return engine.seeded(file) > offset;
}

/** Learn the command names of the most recent megabyte of a shell history file; true when the file changed. */
async function learnShell(engine: GhostEngine, path: string): Promise<boolean> {
  let size: number;
  try { size = (await stat(path)).size; } catch { return false; }
  if (size === engine.seeded(path)) return false;
  const length = Math.min(size, SHELL_WINDOW), handle = await open(path, 'r');
  try {
    const buffer = Buffer.alloc(length);
    await handle.read(buffer, 0, length, size - length);
    engine.learnCommandWords(commandNames(buffer.toString('utf8')));
  } finally { await handle.close(); }
  engine.setSeeded(path, size);
  return true;
}

/** Seed the engine from the configured history; incremental, so a later run reads only what is new. True when anything changed. */
export async function seedEngine(engine: GhostEngine, options: SeedOptions, sessionsDir: string, currentSession: string | undefined, aborted: () => boolean): Promise<boolean> {
  let changed = false;
  for (const root of [options.piSessions ? sessionsDir : null, options.ompSessions]) {
    if (!root) continue;
    for (const file of await sessionFiles(root)) {
      if (aborted()) return changed;
      if (file !== currentSession) changed = await learnSession(engine, file, aborted) || changed;
    }
  }
  for (const path of options.shellHistory) {
    if (aborted()) return changed;
    changed = await learnShell(engine, path) || changed;
  }
  return changed;
}
