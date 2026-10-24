import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { appendFileSync, chmodSync, existsSync, lstatSync, mkdirSync, mkdtempSync, readFileSync, readlinkSync, rmSync, statSync, symlinkSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { Checkpoints, CheckpointError, describeRestore, promptLabel, relativeTime } from '../../dotfiles/pi/extensions/checkpoint-core.ts';

const git = process.env.CHECKPOINT_TEST_GIT ?? 'git';
const sh = (cwd, ...args) => execFileSync(git, args, { cwd, encoding: 'utf8', env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' } });
const fixture = (prefix) => mkdtempSync(join(tmpdir(), `ckpt-${prefix}-`));
const config = (dataDir, extra = {}) => ({ git, dataDir, maxFiles: 1000, maxFileBytes: 1024, ...extra });
const write = (root, path, text) => { mkdirSync(join(root, path, '..'), { recursive: true }); writeFileSync(join(root, path), text); };
const read = (root, path) => readFileSync(join(root, path), 'utf8');

function project() {
  const root = fixture('project');
  sh(root, 'init', '-q', '-b', 'main');
  write(root, 'a.txt', 'original a\n');
  write(root, 'sub/b.txt', 'original b\n');
  write(root, '.gitignore', 'ignored.log\nbuild/\n');
  write(root, 'ignored.log', 'ignored\n');
  sh(root, 'add', '-A');
  sh(root, 'commit', '-qm', 'init');
  return root;
}

test('a restore reverts edits, removes created files and brings back deleted ones, and spares ignored files', async () => {
  const root = project(), data = fixture('data');
  const store = await Checkpoints.open(root, 'session-1', config(data));
  write(root, 'untracked.txt', 'untracked before\n');
  const start = await store.snapshot('start', 's1');
  assert.match(start.commit, /^[0-9a-f]{40}$/);
  assert.match(start.head, /^[0-9a-f]{40}$/);

  write(root, 'a.txt', 'agent edit\n');
  rmSync(join(root, 'sub/b.txt'));
  write(root, 'created.txt', 'new\n');
  write(root, 'ignored.log', 'changed but ignored\n');
  write(root, 'build/out.js', 'ignored build output\n');

  const preview = await store.preview(start.commit);
  assert.deepEqual(preview.map((c) => `${c.status} ${c.path}`).sort(), ['A sub/b.txt', 'D created.txt', 'M a.txt']);
  assert.deepEqual(describeRestore(preview), ['↺ revert  a.txt', '+ restore sub/b.txt', '− remove  created.txt']);

  const { before, changes } = await store.restore(start.commit, 's1');
  assert.equal(changes.length, 3);
  assert.equal(read(root, 'a.txt'), 'original a\n');
  assert.equal(read(root, 'sub/b.txt'), 'original b\n');
  assert.equal(existsSync(join(root, 'created.txt')), false);
  assert.equal(read(root, 'untracked.txt'), 'untracked before\n', 'files that were untracked at the snapshot survive');
  assert.equal(read(root, 'ignored.log'), 'changed but ignored\n', 'ignored files are never touched');
  assert.equal(existsSync(join(root, 'build/out.js')), true);

  // The restore can itself be undone: `before` holds the state the agent left.
  await store.restore(before.commit, 's1');
  assert.equal(read(root, 'a.txt'), 'agent edit\n');
  assert.equal(existsSync(join(root, 'sub/b.txt')), false);
  assert.equal(read(root, 'created.txt'), 'new\n');
});

test('the project repository is never touched: its index, refs and history are what they were', async () => {
  const root = project(), data = fixture('data');
  const state = () => [sh(root, 'status', '--porcelain'), sh(root, 'for-each-ref'), sh(root, 'rev-parse', 'HEAD'), sh(root, 'stash', 'list')].join('|');
  const store = await Checkpoints.open(root, 's', config(data));
  const before = state();
  const snapshot = await store.snapshot('x', 's');
  assert.equal(state(), before, 'snapshotting leaves git status, refs and HEAD alone');
  write(root, 'a.txt', 'dirty\n');
  const dirty = state();
  await store.restore(snapshot.commit, 's');
  assert.notEqual(state(), dirty);
  assert.equal(sh(root, 'for-each-ref'), before.split('|')[1]);
  assert.equal(existsSync(join(root, '.git', 'refs', 'pi')), false);
  assert.ok(store.dir.startsWith(data), 'the private repository lives outside the project');
});

test('a nested repository without commits and a file over the size limit are left out and left alone', async () => {
  const root = project(), data = fixture('data');
  const nested = join(root, 'vendor', 'tool');
  mkdirSync(nested, { recursive: true });
  sh(nested, 'init', '-q');
  write(nested, 'n.txt', 'nested\n');
  write(root, 'big.bin', 'x'.repeat(5000));
  const store = await Checkpoints.open(root, 's', config(data));
  const start = await store.snapshot('start', 's');
  const listing = sh(store.dir, '--git-dir', store.dir, 'ls-tree', '-r', '--name-only', start.commit);
  assert.ok(listing.includes('a.txt') && !listing.includes('vendor/') && !listing.includes('big.bin'), listing);
  write(root, 'a.txt', 'edited\n');
  write(nested, 'n.txt', 'edited nested\n');
  write(root, 'big.bin', 'y'.repeat(6000));
  await store.restore(start.commit, 's');
  assert.equal(read(root, 'a.txt'), 'original a\n');
  assert.equal(read(nested, 'n.txt'), 'edited nested\n', 'a nested repository is not ours to rewind');
  assert.equal(statSync(join(root, 'big.bin')).size, 6000, 'an excluded large file is not touched');
});

test('a project with more files than the limit is refused before anything is hashed', async () => {
  const root = fixture('crowded'), data = fixture('data');
  for (let i = 0; i < 12; i++) write(root, `f${i}.txt`, 'x');
  const store = await Checkpoints.open(root, 's', config(data, { maxFiles: 10 }));
  await assert.rejects(store.snapshot('x', 's'), (error) => error instanceof CheckpointError && /12 new files/.test(error.message));
});

test('a directory outside git is a project of its own, and sessions keep separate indexes', async () => {
  const root = fixture('plain'), data = fixture('data');
  write(root, 'notes.md', 'one\n');
  const first = await Checkpoints.open(root, 'session-a', config(data));
  const second = await Checkpoints.open(root, 'session-b', config(data));
  assert.equal(first.dir, second.dir, 'sessions of one project share objects');
  const a = await first.snapshot('a', 'a');
  assert.equal(a.head, undefined, 'no repository, no HEAD');
  write(root, 'notes.md', 'two\n');
  const b = await second.snapshot('b', 'b');
  assert.notEqual(a.tree, b.tree);
  await first.restore(a.commit, 'a');
  assert.equal(read(root, 'notes.md'), 'one\n');
});

test('the executable bit survives a restore', async () => {
  const root = project(), data = fixture('data');
  write(root, 'run.sh', '#!/bin/sh\n');
  chmodSync(join(root, 'run.sh'), 0o755);
  const store = await Checkpoints.open(root, 's', config(data));
  const start = await store.snapshot('start', 's');
  rmSync(join(root, 'run.sh'));
  await store.restore(start.commit, 's');
  assert.ok((statSync(join(root, 'run.sh')).mode & 0o111) !== 0);
});

test('prune drops old snapshots and keeps the recent ones; treeOf reports what is gone', async () => {
  const root = project(), data = fixture('data');
  const store = await Checkpoints.open(root, 's', config(data));
  const old = await store.snapshot('old', 's');
  write(root, 'a.txt', 'later\n');
  const recent = await store.snapshot('recent', 's');
  const day = 24 * 3600 * 1000;
  assert.equal(await store.prune(14 * day), 0, 'nothing is old yet');
  assert.equal(await store.prune(14 * day, Date.now() + 15 * day), 2, 'both are past the limit in the future');
  assert.equal(await store.treeOf(old.commit) !== undefined || await store.treeOf(recent.commit) !== undefined, true, 'objects survive until gc runs past the grace period');
  assert.equal(await store.treeOf('0'.repeat(40)), undefined);
});

test('describeRestore caps the list, relativeTime and promptLabel read well', () => {
  const many = Array.from({ length: 15 }, (_, i) => ({ status: 'M', path: `f${i}.ts` }));
  const lines = describeRestore(many, 12);
  assert.equal(lines.length, 13);
  assert.equal(lines.at(-1), '… and 3 more');
  assert.equal(relativeTime(1000, 1000 + 30_000), 'just now');
  assert.equal(relativeTime(0, 5 * 60_000), '5m ago');
  assert.equal(relativeTime(0, 3 * 3600_000), '3h ago');
  assert.equal(relativeTime(0, 2 * 86400_000), '2d ago');
  assert.equal(promptLabel('  Fix the\n  failing test  '), 'Fix the');
  assert.equal(promptLabel('x'.repeat(100)).length, 72);
});

test('a restore refuses to destroy what no snapshot holds: a directory of ignored files where the snapshot has a file', async () => {
  const root = project(), data = fixture('data');
  write(root, '.gitignore', 'ignored.log\nbuild/\n*.secret\n');
  write(root, 'victim', 'a plain file at snapshot time\n');
  const store = await Checkpoints.open(root, 's', config(data));
  const start = await store.snapshot('start', 's');
  rmSync(join(root, 'victim'));
  write(root, 'victim/key.secret', 'ignored, never snapshotted\n');
  await assert.rejects(store.restore(start.commit, 's'), (error) => error instanceof CheckpointError && /would overwrite 1 path/.test(error.message) && /victim/.test(error.message));
  assert.equal(read(root, 'victim/key.secret'), 'ignored, never snapshotted\n', 'nothing was removed');
  await assert.rejects(store.preview(start.commit), /would overwrite/, 'the dialog is never offered either');
});

test('a file that became a symlink is a change, and a restore turns it back', async () => {
  const root = project(), data = fixture('data');
  const store = await Checkpoints.open(root, 's', config(data));
  const start = await store.snapshot('start', 's');
  rmSync(join(root, 'a.txt'));
  symlinkSync('sub/b.txt', join(root, 'a.txt'));
  const preview = await store.preview(start.commit);
  assert.deepEqual(preview.map((c) => `${c.status} ${c.path}`), ['M a.txt']);
  await store.restore(start.commit, 's');
  assert.equal(lstatSync(join(root, 'a.txt')).isSymbolicLink(), false);
  assert.equal(read(root, 'a.txt'), 'original a\n');
});

test('a tracked file that grows past the limit leaves the snapshots and is never overwritten by a restore', async () => {
  const root = project(), data = fixture('data');
  write(root, 'grow.txt', 'small\n');
  const store = await Checkpoints.open(root, 's', config(data));
  const start = await store.snapshot('start', 's');
  write(root, 'grow.txt', 'x'.repeat(5000));
  const later = await store.snapshot('later', 's');
  const listing = sh(store.dir, '--git-dir', store.dir, 'ls-tree', '-r', '--name-only', later.commit);
  assert.ok(!listing.includes('grow.txt'), 'the grown file is out of the new snapshot');
  await assert.rejects(store.restore(start.commit, 's'), /would overwrite 1 path/);
  assert.equal(read(root, 'grow.txt').length, 5000, 'the big file is untouched');
});

test('file names with newlines cannot add exclusion rules, and the project info/exclude is honoured', async () => {
  const root = project(), data = fixture('data');
  write(root, 'big\nsecret', 'x'.repeat(5000));
  write(root, 'local.secret', 'kept out by info/exclude\n');
  appendFileSync(join(root, '.git', 'info', 'exclude'), 'local.secret\n');
  const store = await Checkpoints.open(root, 's', config(data));
  const start = await store.snapshot('start', 's');
  const listing = sh(store.dir, '--git-dir', store.dir, 'ls-tree', '-r', '--name-only', '-z', start.commit).split('\0');
  assert.ok(!listing.includes('big\nsecret') && !listing.includes('local.secret') && listing.includes('a.txt'), JSON.stringify(listing));
  const rules = readFileSync(join(store.dir, 'info', 'exclude'), 'utf8');
  assert.ok(rules.includes('local.secret') && !rules.includes('secret\n/'), 'the private exclude mirrors the project one and holds nothing else');
});

test('a flood of new files after the first snapshot is refused too', async () => {
  const root = project(), data = fixture('data');
  const store = await Checkpoints.open(root, 's', config(data, { maxFiles: 10 }));
  await store.snapshot('start', 's');
  for (let i = 0; i < 12; i++) write(root, `flood/f${i}.txt`, 'x');
  await assert.rejects(store.snapshot('later', 's'), /12 new files/);
});
