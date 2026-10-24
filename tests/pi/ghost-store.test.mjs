import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, rm, utimes, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { GhostEngine, parseSnapshot } from '../../dotfiles/pi/extensions/ghost-core.ts';
import { commitState } from '../../dotfiles/pi/extensions/ghost-store.ts';

const state = dir => readFile(join(dir, 'ghost-text-state.json'), 'utf8').then(text => parseSnapshot(JSON.parse(text)));
const scratch = async run => {
  const dir = await mkdtemp(join(tmpdir(), 'ghost-store-'));
  try { await run(dir); } finally { await rm(dir, { recursive: true, force: true }); }
};

test('sessions sharing a state directory keep each other\'s learning', () => scratch(async dir => {
  const a = new GhostEngine(['the\t0.05']), b = new GhostEngine(['the\t0.05']);
  a.observe('alphaword alphaword alphaword'); b.observe('betaword betaword betaword');
  assert.equal(await commitState(a, dir), true);
  assert.equal(await commitState(b, dir), true);
  const saved = await state(dir);
  assert.equal(saved.words.alphaword, 3);
  assert.equal(saved.words.betaword, 3);
  assert.equal(b.snapshot().words.alphaword, 3, 'the later session adopts what the earlier one learned');
  assert.equal(await commitState(a, dir), true);
  assert.equal(a.snapshot().words.betaword, 3, 'the earlier session adopts it at its next commit');
}));

test('committing again without new learning counts nothing twice', () => scratch(async dir => {
  const e = new GhostEngine(['the\t0.05']);
  e.observe('alphaword');
  await commitState(e, dir); await commitState(e, dir);
  assert.equal((await state(dir)).words.alphaword, 1);
}));
test('words named like Object prototype members merge as ordinary counts', () => scratch(async dir => {
  const a = new GhostEngine(['the\t0.05']), b = new GhostEngine(['the\t0.05']);
  a.observe('constructor constructor'); b.observe('constructor');
  await commitState(a, dir); await commitState(b, dir);
  const saved = await state(dir);
  assert.equal(saved.words.constructor, 3);
  assert.equal(b.snapshot().words.constructor, 3);
}));

test('counts from concurrent processes add up exactly', () => scratch(async dir => {
  const worker = new URL('./ghost-store.worker.mjs', import.meta.url).pathname, workers = 6, rounds = 20;
  const codes = await Promise.all(Array.from({ length: workers }, (_, id) => {
    const { promise, resolve } = Promise.withResolvers();
    spawn(process.execPath, [worker, dir, String(id), String(rounds)], { stdio: 'inherit' }).on('exit', resolve);
    return promise;
  }));
  assert.deepEqual(codes, Array(workers).fill(0));
  const saved = await state(dir);
  assert.equal(saved.words.sharedword, workers * rounds);
  for (const id of 'abcdef') assert.equal(saved.words['unique' + id], rounds, id);
}));

test('a stale lock is taken over; a fresh one makes the commit give up without losing learning', () => scratch(async dir => {
  const lock = join(dir, 'ghost-text-state.lock'), e = new GhostEngine(['the\t0.05']);
  await writeFile(lock, '1 0');
  const old = new Date(Date.now() - 60_000);
  await utimes(lock, old, old);
  e.observe('alphaword');
  assert.equal(await commitState(e, dir, 500), true);
  await writeFile(lock, '1 0');
  e.observe('alphaword');
  assert.equal(await commitState(e, dir, 150), false);
  await rm(lock);
  assert.equal(await commitState(e, dir, 500), true);
  assert.equal((await state(dir)).words.alphaword, 2);
}));
