import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm, symlink, chmod, stat, realpath } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.env.PI_TEST_PACKAGE_DIR;
assert.ok(root, 'PI_TEST_PACKAGE_DIR must name the real Pi installation');
const requirePi = createRequire(join(root, 'package.json'));
const jiti = requirePi('jiti').createJiti(import.meta.url, { alias: {
  '@earendil-works/pi-coding-agent': join(root, 'dist/index.js'),
} });
const { createFormatOnWrite } = await jiti.import('../../dotfiles/pi/extensions/format-on-write.ts');

const upper = "let d='';process.stdin.setEncoding('utf8').on('data',c=>d+=c).on('end',()=>process.stdout.write(d.toUpperCase()))";
const formatter = (name, extension, script = upper, extra = {}) => ({
  name, command: process.execPath, args: ['-e', script], extensions: [extension], rootMarkers: [], requireRootMarker: false, ...extra,
});
const options = (formatters, extra = {}) => ({ formatters, timeoutMs: 5000, maxFileBytes: 1024 * 1024, maxOutputBytes: 4 * 1024 * 1024, maxDiffLines: 40, ...extra });

async function fixture(formatters, extra) {
  const dir = await realpath(await mkdtemp(join(tmpdir(), 'pi-format-on-write-')));
  const events = new Map(), notices = [];
  createFormatOnWrite({ on: (name, handler) => events.set(name, handler) }, options(formatters, extra));
  const ctx = { cwd: dir, ui: { notify: message => notices.push(message) } };
  const result = (toolName, path, extra = {}) => events.get('tool_result')({
    type: 'tool_result', toolCallId: 'call', toolName, input: { path }, isError: false,
    content: [{ type: 'text', text: 'ok' }], details: undefined, ...extra,
  }, ctx);
  return { dir, notices, result, ctx, close: () => rm(dir, { recursive: true, force: true }) };
}
const note = reply => reply.content.slice(1).map(item => item.text).join('\n');

test('a successful edit is formatted on disk and the model is told exactly what changed', async () => {
  const f = await fixture([formatter('up', '.x')]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'hello\nworld\n');
    const reply = await f.result('edit', 'a.x');
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'HELLO\nWORLD\n');
    assert.deepEqual(reply.content[0], { type: 'text', text: 'ok' });
    assert.equal(reply.content.length, 2);
    assert.match(note(reply), /^Formatted with up: \+2\/-2 lines\./);
    assert.match(note(reply), /@@ -1,2 \+1,2 @@\n-hello\n-world\n\+HELLO\n\+WORLD$/);
  } finally { await f.close(); }
});

test('write results are formatted too, and relative paths may carry the @ prefix', async () => {
  const f = await fixture([formatter('up', '.x')]);
  try {
    await mkdir(join(f.dir, 'sub'));
    await writeFile(join(f.dir, 'sub/new.x'), 'fresh\n');
    const reply = await f.result('write', '@sub/new.x');
    assert.equal(await readFile(join(f.dir, 'sub/new.x'), 'utf8'), 'FRESH\n');
    assert.match(note(reply), /Formatted with up/);
  } finally { await f.close(); }
});

test('already formatted files are left alone and the result is not touched', async () => {
  const f = await fixture([formatter('up', '.x')]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'DONE\n');
    assert.equal(await f.result('edit', 'a.x'), undefined);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'DONE\n');
  } finally { await f.close(); }
});

test('only successful edit and write results are considered', async () => {
  const f = await fixture([formatter('up', '.x')]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'lower\n');
    assert.equal(await f.result('edit', 'a.x', { isError: true }), undefined);
    for (const tool of ['bash', 'read', 'grep', 'lsp']) assert.equal(await f.result(tool, 'a.x'), undefined);
    assert.equal(await f.result('edit', undefined), undefined);
    assert.equal(await f.result('edit', 42), undefined);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'lower\n');
  } finally { await f.close(); }
});

test('a formatter that rejects the file leaves it and the result unchanged', async () => {
  const f = await fixture([formatter('bad', '.x', "process.stdin.resume();process.stderr.write('parse error');process.exitCode=2")]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'broken(\n');
    assert.equal(await f.result('edit', 'a.x'), undefined);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'broken(\n');
    assert.deepEqual(f.notices, []);
  } finally { await f.close(); }
});

test('files outside the session directory are never rewritten', async () => {
  const f = await fixture([formatter('up', '.x')]);
  const other = await mkdtemp(join(tmpdir(), 'pi-format-outside-'));
  try {
    await writeFile(join(other, 'a.x'), 'lower\n');
    assert.equal(await f.result('write', join(other, 'a.x')), undefined);
    assert.equal(await f.result('write', '../' + join(other, 'a.x').split('/').slice(-2).join('/')), undefined);
    assert.equal(await readFile(join(other, 'a.x'), 'utf8'), 'lower\n');
  } finally { await f.close(); await rm(other, { recursive: true, force: true }); }
});

test('a symlink is skipped so its target is never rewritten through it', async () => {
  const f = await fixture([formatter('up', '.x')]);
  const other = await mkdtemp(join(tmpdir(), 'pi-format-link-'));
  try {
    await writeFile(join(other, 'target.x'), 'lower\n');
    await symlink(join(other, 'target.x'), join(f.dir, 'link.x'));
    assert.equal(await f.result('edit', 'link.x'), undefined);
    assert.equal(await readFile(join(other, 'target.x'), 'utf8'), 'lower\n');
  } finally { await f.close(); await rm(other, { recursive: true, force: true }); }
});

test('oversized, non-UTF-8 and unknown-extension files are skipped', async () => {
  const f = await fixture([formatter('up', '.x')], { maxFileBytes: 16 });
  try {
    await writeFile(join(f.dir, 'big.x'), 'lower '.repeat(10));
    assert.equal(await f.result('edit', 'big.x'), undefined);
    await writeFile(join(f.dir, 'bin.x'), Buffer.from([0x61, 0xff, 0x62]));
    assert.equal(await f.result('edit', 'bin.x'), undefined);
    await writeFile(join(f.dir, 'notes.txt'), 'lower\n');
    assert.equal(await f.result('edit', 'notes.txt'), undefined);
    assert.equal(await readFile(join(f.dir, 'big.x'), 'utf8'), 'lower '.repeat(10));
    assert.deepEqual([...await readFile(join(f.dir, 'bin.x'))], [0x61, 0xff, 0x62]);
    assert.equal(await readFile(join(f.dir, 'notes.txt'), 'utf8'), 'lower\n');
  } finally { await f.close(); }
});

test('a formatter that needs a project marker runs only where the project configures it', async () => {
  const f = await fixture([formatter('gated', '.x', upper, { requireRootMarker: true, rootMarkers: ['fmt.json'] })]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'lower\n');
    assert.equal(await f.result('edit', 'a.x'), undefined);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'lower\n');
    await writeFile(join(f.dir, 'fmt.json'), '{}');
    assert.match(note(await f.result('edit', 'a.x')), /Formatted with gated/);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'LOWER\n');
  } finally { await f.close(); }
});

test('file mode survives formatting', async () => {
  const f = await fixture([formatter('up', '.x')]);
  try {
    await writeFile(join(f.dir, 'run.x'), 'lower\n');
    await chmod(join(f.dir, 'run.x'), 0o755);
    await f.result('edit', 'run.x');
    assert.equal((await stat(join(f.dir, 'run.x'))).mode & 0o777, 0o755);
  } finally { await f.close(); }
});

test('concurrent results for one file are serialized: exactly one reports the change', async () => {
  const slow = "let d='';process.stdin.setEncoding('utf8').on('data',c=>d+=c).on('end',()=>setTimeout(()=>process.stdout.write(d.toUpperCase()),150))";
  const f = await fixture([formatter('slow', '.x', slow)]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'lower\n');
    const replies = await Promise.all([f.result('edit', 'a.x'), f.result('edit', 'a.x')]);
    assert.equal(replies.filter(Boolean).length, 1);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'LOWER\n');
  } finally { await f.close(); }
});

test('a missing formatter executable is reported once and then skipped for the session', async () => {
  const f = await fixture([{ ...formatter('gone', '.x'), command: '/nonexistent/formatter' }]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'lower\n');
    assert.equal(await f.result('edit', 'a.x'), undefined);
    assert.equal(await f.result('edit', 'a.x'), undefined);
    assert.equal(f.notices.length, 1);
    assert.match(f.notices[0], /gone/);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'lower\n');
  } finally { await f.close(); }
});

test('the report is cut at the diff budget so one huge reformat cannot flood the context', async () => {
  const f = await fixture([formatter('up', '.x')], { maxDiffLines: 6 });
  try {
    await writeFile(join(f.dir, 'a.x'), Array.from({ length: 50 }, (_, i) => `line${i}`).join('\n') + '\n');
    const text = note(await f.result('edit', 'a.x'));
    assert.match(text, /\+50\/-50 lines/);
    assert.match(text, /… \d+ more diff lines$/);
    assert.ok(text.split('\n').length < 14);
  } finally { await f.close(); }
});

test('a formatter that exits cleanly with empty output never blanks a non-empty file', async () => {
  const f = await fixture([formatter('mute', '.x', 'process.stdin.resume()')]);
  try {
    await writeFile(join(f.dir, 'a.x'), 'keep\n');
    assert.equal(await f.result('edit', 'a.x'), undefined);
    assert.equal(await readFile(join(f.dir, 'a.x'), 'utf8'), 'keep\n');
  } finally { await f.close(); }
});
