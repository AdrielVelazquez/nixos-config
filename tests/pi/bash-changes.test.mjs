import test from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { mkdtemp, mkdir, writeFile, readFile, rm, realpath, utimes } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.env.PI_TEST_PACKAGE_DIR;
assert.ok(root, 'PI_TEST_PACKAGE_DIR must name the real Pi installation');
const jiti = createRequire(join(root, 'package.json'))('jiti').createJiti(import.meta.url, { alias: { '@earendil-works/pi-coding-agent': join(root, 'dist/index.js') } });
const { fingerprint, changedBetween, describeChanges } = await jiti.import('../../dotfiles/pi/extensions/bash-changes-core.ts');
const { createFormatOnWrite } = await jiti.import('../../dotfiles/pi/extensions/format-on-write.ts');

const git = (dir, ...args) => execFileSync('git', args, { cwd: dir, env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' }, stdio: 'pipe' });
async function repo() {
  const dir = await realpath(await mkdtemp(join(tmpdir(), 'pi-bash-changes-')));
  git(dir, 'init', '-q', '-b', 'main');
  await writeFile(join(dir, 'tracked.x'), 'one\n');
  git(dir, 'add', '-A'); git(dir, 'commit', '-qm', 'init');
  return { dir, close: () => rm(dir, { recursive: true, force: true }) };
}
const later = async (path) => { const when = new Date(Date.now() + 5000); await utimes(path, when, when); };

test('fingerprint names nothing outside a repository, and changedBetween only what a command wrote', async () => {
  const plain = await realpath(await mkdtemp(join(tmpdir(), 'pi-bash-plain-')));
  try { assert.equal(await fingerprint(plain), undefined, 'not a git tree: no stamps'); } finally { await rm(plain, { recursive: true, force: true }); }
  const r = await repo();
  try {
    await writeFile(join(r.dir, 'dirty-before.x'), 'was already dirty\n');
    await mkdir(join(r.dir, 'node_modules/pkg'), { recursive: true });
    await mkdir(join(r.dir, 'vendor'), { recursive: true });
    const before = await fingerprint(r.dir);
    assert.ok(before.has(join(r.dir, 'dirty-before.x')));
    // The "command": a new file, an edit of a tracked file, noise, a deletion of a tracked file.
    await writeFile(join(r.dir, 'new.x'), 'fresh\n');
    await writeFile(join(r.dir, 'tracked.x'), 'two lines\nnow\n');
    await writeFile(join(r.dir, 'node_modules/pkg/index.js'), 'x');
    await writeFile(join(r.dir, 'vendor/v.go'), 'x');
    const after = await fingerprint(r.dir);
    assert.deepEqual(changedBetween(before, after).map((p) => p.slice(r.dir.length + 1)), ['new.x', 'tracked.x'], 'a file that was already dirty and untouched is not the command\'s; noise is left out');
    await rm(join(r.dir, 'new.x'));
    assert.deepEqual(changedBetween(after, await fingerprint(r.dir)), [], 'a deleted file is not a changed file');
    // Rewritten with the same size in the same instant would be missed by mtime alone: the stamp carries sub-millisecond mtime.
    await writeFile(join(r.dir, 'dirty-before.x'), 'was already DIRTY\n');
    await later(join(r.dir, 'dirty-before.x'));
    assert.deepEqual(changedBetween(before, await fingerprint(r.dir)).map((p) => p.slice(r.dir.length + 1)).includes('dirty-before.x'), true);
  } finally { await r.close(); }
});

test('describeChanges is one sentence and caps the list', () => {
  assert.equal(describeChanges(['/p/a.go'], '/p'), 'This command changed 1 file: a.go.');
  const many = Array.from({ length: 11 }, (_, n) => `/p/sub/f${n}.go`);
  assert.equal(describeChanges(many, '/p'), `This command changed 11 files: ${many.slice(0, 8).map((m) => m.slice(3)).join(', ')}, and 3 more.`);
});

const upper = "let d='';process.stdin.setEncoding('utf8').on('data',c=>d+=c).on('end',()=>process.stdout.write(d.toUpperCase()))";
const options = (extra = {}) => ({ formatters: [{ name: 'up', command: process.execPath, args: ['-e', upper], extensions: ['.x'], rootMarkers: [], requireRootMarker: false }], timeoutMs: 5000, maxFileBytes: 1024 * 1024, maxOutputBytes: 4 * 1024 * 1024, maxDiffLines: 40, ...extra });
async function session(dir, extra) {
  const events = new Map(), notices = [];
  createFormatOnWrite({ on: (name, handler) => events.set(name, handler) }, options(extra));
  const ctx = { cwd: dir, ui: { notify: (m) => notices.push(m) } };
  return {
    call: (id = 'c1') => events.get('tool_call')({ type: 'tool_call', toolCallId: id, toolName: 'bash', input: { command: 'cat > a.x' } }, ctx),
    result: (id = 'c1', extra = {}) => events.get('tool_result')({ type: 'tool_result', toolCallId: id, toolName: 'bash', input: { command: 'cat > a.x' }, isError: false, content: [{ type: 'text', text: '(no output)' }], details: undefined, ...extra }, ctx),
  };
}
const notes = (reply) => reply.content.slice(1).map((item) => item.text).join('\n');

test('only files the command itself wrote are named, and the formatter runs on them', async () => {
  const r = await repo();
  try {
    await writeFile(join(r.dir, 'already.x'), 'untouched by the command\n');
    const s = await session(r.dir);
    await s.call();
    await writeFile(join(r.dir, 'a.x'), 'hello\nworld\n');
    await writeFile(join(r.dir, 'notes.md'), 'no formatter for this\n');
    const reply = await s.result();
    assert.match(notes(reply), /^This command changed 2 files: a\.x, notes\.md\./m);
    assert.match(notes(reply), /Formatted a\.x with up: \+2\/-2 lines/);
    assert.equal(await readFile(join(r.dir, 'a.x'), 'utf8'), 'HELLO\nWORLD\n');
    assert.equal(await readFile(join(r.dir, 'notes.md'), 'utf8'), 'no formatter for this\n', 'no formatter for the extension: left as written');
    assert.equal(await readFile(join(r.dir, 'already.x'), 'utf8'), 'untouched by the command\n', 'not written by this command: never reformatted');
  } finally { await r.close(); }
});

test('a failed command reports what it changed but is not formatted; a command that changed nothing adds nothing', async () => {
  const r = await repo();
  try {
    const s = await session(r.dir);
    await s.call('failing');
    await writeFile(join(r.dir, 'a.x'), 'half written\n');
    const failed = await s.result('failing', { isError: true });
    assert.match(notes(failed), /^This command changed 1 file: a\.x\.$/);
    assert.equal(await readFile(join(r.dir, 'a.x'), 'utf8'), 'half written\n');
    await s.call('quiet');
    assert.equal(await s.result('quiet'), undefined, 'ls, grep, go test: nothing to say');
  } finally { await r.close(); }
});

test('bash is left alone when disabled, outside git, without a before-stamp, and for other tools', async () => {
  const r = await repo();
  try {
    const off = await session(r.dir, { afterBash: false });
    await off.call();
    await writeFile(join(r.dir, 'a.x'), 'hello\n');
    assert.equal(await off.result(), undefined);
    assert.equal(await readFile(join(r.dir, 'a.x'), 'utf8'), 'hello\n');
    const on = await session(r.dir);
    assert.equal(await on.result('never-stamped'), undefined, 'no tool_call was seen for this id');
  } finally { await r.close(); }
  const plain = await realpath(await mkdtemp(join(tmpdir(), 'pi-bash-plain-')));
  try {
    const s = await session(plain);
    await s.call();
    await writeFile(join(plain, 'a.x'), 'hello\n');
    assert.equal(await s.result(), undefined, 'not a git tree');
  } finally { await rm(plain, { recursive: true, force: true }); }
});
