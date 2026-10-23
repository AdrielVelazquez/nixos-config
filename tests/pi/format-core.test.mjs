import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  cargoEdition, isInside, lineDiff, resolveToolPath, runFormatter, selectFormatter,
} from '../../dotfiles/pi/extensions/format-core.ts';

const spec = (name, extensions, extra = {}) => ({
  name, command: process.execPath, args: [], extensions, rootMarkers: [], requireRootMarker: false, ...extra,
});
const node = (script, args = []) => ({ command: process.execPath, args: ['-e', script, '--', ...args] });
const upper = "let d='';process.stdin.setEncoding('utf8').on('data',c=>d+=c).on('end',()=>process.stdout.write(d.toUpperCase()))";
async function tree(files) {
  const dir = await mkdtemp(join(tmpdir(), 'pi-format-core-'));
  for (const [name, text] of Object.entries(files)) {
    await mkdir(join(dir, name, '..'), { recursive: true });
    await writeFile(join(dir, name), text);
  }
  return dir;
}

test('tool paths drop the @ prefix, expand ~ and resolve against the session directory', () => {
  assert.equal(resolveToolPath('@src/a.go', '/work'), '/work/src/a.go');
  assert.equal(resolveToolPath('../b.go', '/work/app'), '/work/b.go');
  assert.equal(resolveToolPath('/abs/c.go', '/work'), '/abs/c.go');
  assert.equal(resolveToolPath('~/d.go', '/work'), join(process.env.HOME, 'd.go'));
  assert.equal(isInside('/work', '/work/a/b.go'), true);
  assert.equal(isInside('/work', '/work'), false);
  assert.equal(isInside('/work', '/workshop/a.go'), false);
  assert.equal(isInside('/work', '/work/../etc/passwd'), false);
});

test('the first declared formatter whose extension matches wins, case-insensitively', async () => {
  const dir = await tree({ 'a/x.go': '' });
  const formatters = [spec('first', ['.go']), spec('second', ['.go', '.mod']), spec('lua', ['.lua'])];
  assert.equal(selectFormatter(formatters, join(dir, 'a/x.go'), dir).name, 'first');
  assert.equal(selectFormatter(formatters, join(dir, 'a/x.GO'), dir).name, 'first');
  assert.equal(selectFormatter(formatters, join(dir, 'a/go.mod'), dir).name, 'second');
  assert.equal(selectFormatter(formatters, join(dir, 'a/x.rs'), dir), undefined);
  assert.equal(selectFormatter(formatters, join(dir, 'a/Makefile'), dir), undefined);
  await rm(dir, { recursive: true });
});

test('marker-gated formatters run only below a marker that lies inside the session root', async () => {
  const dir = await tree({ 'biome.json': '{}', 'with/deep/x.ts': '', 'proj/.editorconfig': '', 'proj/src/y.sh': '' });
  const gated = (name, ext, markers) => spec(name, [ext], { requireRootMarker: true, rootMarkers: markers });
  const formatters = [gated('biome', '.ts', ['biome.json']), gated('shfmt', '.sh', ['.editorconfig'])];
  assert.equal(selectFormatter(formatters, join(dir, 'with/deep/x.ts'), dir).name, 'biome');
  assert.equal(selectFormatter(formatters, join(dir, 'proj/src/y.sh'), join(dir, 'proj')).name, 'shfmt');
  // the biome.json above the session root is not the project's config
  assert.equal(selectFormatter(formatters, join(dir, 'with/deep/x.ts'), join(dir, 'with')), undefined);
  // a marker elsewhere in the tree does not apply to a sibling project
  assert.equal(selectFormatter(formatters, join(dir, 'with/deep/z.sh'), dir), undefined);
  // an optional-marker formatter ignores markers entirely
  assert.equal(selectFormatter([spec('go', ['.go'], { rootMarkers: ['go.mod'] })], join(dir, 'a.go'), dir).name, 'go');
  await rm(dir, { recursive: true });
});

test('a changed line becomes one unified hunk with context and exact counts', () => {
  const diff = lineDiff('a\nb\nc\nd\ne\n', 'a\nb\nC\nd\ne\n', { context: 1 });
  assert.deepEqual({ added: diff.added, removed: diff.removed }, { added: 1, removed: 1 });
  assert.equal(diff.text, '@@ -2,3 +2,3 @@\n b\n-c\n+C\n d');
});

test('separate changes produce separate hunks and inserted lines shift later line numbers', () => {
  const before = Array.from({ length: 20 }, (_, i) => `l${i + 1}`).join('\n') + '\n';
  const lines = before.trimEnd().split('\n');
  lines.splice(2, 0, 'new');
  lines[lines.length - 3] = 'CHANGED';
  const diff = lineDiff(before, lines.join('\n') + '\n', { context: 1 });
  assert.deepEqual({ added: diff.added, removed: diff.removed }, { added: 2, removed: 1 });
  assert.equal(diff.text.split('\n').filter(l => l.startsWith('@@')).length, 2);
  assert.match(diff.text, /^@@ -2,2 \+2,3 @@\n l2\n\+new\n l3\n@@ -17,3 \+18,3 @@\n l17\n-l18\n\+CHANGED\n l19$/);
});

test('identical text has no diff, and a final-newline-only change is described instead of drawn', () => {
  assert.equal(lineDiff('a\nb\n', 'a\nb\n'), undefined);
  assert.deepEqual(lineDiff('a\nb', 'a\nb\n'), { added: 0, removed: 0, text: '(final newline added)' });
  assert.deepEqual(lineDiff('a\nb\n', 'a\nb'), { added: 0, removed: 0, text: '(final newline removed)' });
});

test('long diffs are cut at the line budget with an exact omission count; huge ones keep only counts', () => {
  const before = Array.from({ length: 100 }, (_, i) => `x${i}`).join('\n') + '\n';
  const after = Array.from({ length: 100 }, (_, i) => `y${i}`).join('\n') + '\n';
  const cut = lineDiff(before, after, { context: 0, maxLines: 10 });
  assert.deepEqual({ added: cut.added, removed: cut.removed }, { added: 100, removed: 100 });
  const rows = cut.text.split('\n');
  assert.equal(rows.length, 11);
  assert.match(rows.at(-1), /^… 191 more diff lines$/);
  const big = lineDiff(Array.from({ length: 3000 }, (_, i) => `a${i}`).join('\n'), Array.from({ length: 3000 }, (_, i) => `b${i}`).join('\n'));
  assert.deepEqual({ added: big.added, removed: big.removed }, { added: 3000, removed: 3000 });
  assert.match(big.text, /^\(diff omitted: too large to compare\)$/);
});

test('the formatter reads the file on stdin and its stdout replaces it', async () => {
  const result = await runFormatter({ ...spec('up', ['.x']), ...node(upper) }, { absPath: '/tmp/a.x', input: 'hello\n', timeoutMs: 5000, maxOutputBytes: 1024 });
  assert.deepEqual(result, { ok: true, output: 'HELLO\n' });
});

test('placeholders become the absolute file, the file directory is the working directory', async () => {
  const dir = await tree({ 'sub/a.x': '' });
  const script = "process.stdin.resume().on('end',()=>process.stdout.write(JSON.stringify({cwd:process.cwd(),argv:process.argv.slice(1)})))";
  const result = await runFormatter({ ...spec('echo', ['.x']), ...node(script, ['--name={file}', 'fixed']) },
    { absPath: join(dir, 'sub/a.x'), input: '', timeoutMs: 5000, maxOutputBytes: 1024 });
  const seen = JSON.parse(result.output);
  assert.equal(seen.cwd, await import('node:fs/promises').then(fs => fs.realpath(join(dir, 'sub'))));
  assert.deepEqual(seen.argv, [`--name=${join(dir, 'sub/a.x')}`, 'fixed']);
  await rm(dir, { recursive: true });
});

test('the Cargo edition comes from the nearest manifest, through workspace inheritance, else 2021', async () => {
  const dir = await tree({
    'plain/src/lib.rs': '',
    'old/Cargo.toml': '[package]\nname = "old"\nedition = "2018"\n',
    'old/src/lib.rs': '',
    'ws/Cargo.toml': '[workspace]\nmembers = ["m"]\n[workspace.package]\nedition = "2024"\n',
    'ws/m/Cargo.toml': '[package]\nname = "m"\nedition.workspace = true\n',
    'ws/m/src/lib.rs': '',
  });
  assert.equal(cargoEdition(join(dir, 'old/src/lib.rs'), dir), '2018');
  assert.equal(cargoEdition(join(dir, 'ws/m/src/lib.rs'), dir), '2024');
  assert.equal(cargoEdition(join(dir, 'plain/src/lib.rs'), dir), '2021');
  const result = await runFormatter({ ...spec('rust', ['.rs']), ...node("process.stdin.resume().on('end',()=>process.stdout.write(process.argv[1]))", ['{cargoEdition}']) },
    { absPath: join(dir, 'old/src/lib.rs'), input: '', timeoutMs: 5000, maxOutputBytes: 1024, root: dir });
  assert.equal(result.output, '2018');
  await rm(dir, { recursive: true });
});

test('a failing formatter reports its exit status and stderr without output', async () => {
  const result = await runFormatter({ ...spec('bad', ['.x']), ...node("process.stderr.write('syntax error\\n');process.stdin.resume();process.exitCode=3") },
    { absPath: '/tmp/a.x', input: 'x', timeoutMs: 5000, maxOutputBytes: 1024 });
  assert.deepEqual(result, { ok: false, reason: 'exit 3: syntax error' });
});

test('a hung formatter is killed at the deadline', async () => {
  const dir = await tree({});
  const pidFile = join(dir, 'pid');
  const script = "require('fs').writeFileSync(process.argv[1],String(process.pid));setInterval(()=>{},1000)";
  const started = Date.now();
  const result = await runFormatter({ ...spec('hang', ['.x']), ...node(script, [pidFile]) },
    { absPath: '/tmp/a.x', input: 'x', timeoutMs: 300, maxOutputBytes: 1024 });
  assert.deepEqual(result, { ok: false, reason: 'timed out after 300 ms' });
  assert.ok(Date.now() - started < 4000);
  const pid = Number(await readFile(pidFile, 'utf8'));
  await new Promise(resolve => setTimeout(resolve, 100));
  assert.throws(() => process.kill(pid, 0), { code: 'ESRCH' });
  await rm(dir, { recursive: true });
});

test('output beyond the budget is refused and the process is stopped', async () => {
  const result = await runFormatter({ ...spec('flood', ['.x']), ...node("process.stdin.resume();const c='x'.repeat(65536);let n=0;(function w(){while(n++<64)if(!process.stdout.write(c))return process.stdout.once('drain',w)})()") },
    { absPath: '/tmp/a.x', input: 'x', timeoutMs: 5000, maxOutputBytes: 1024 });
  assert.deepEqual(result, { ok: false, reason: 'output exceeded 1024 bytes' });
});

test('a formatter that never reads stdin does not crash the writer', async () => {
  const big = 'y'.repeat(4 * 1024 * 1024);
  const result = await runFormatter({ ...spec('deaf', ['.x']), ...node("process.stdout.write('done')") },
    { absPath: '/tmp/a.x', input: big, timeoutMs: 5000, maxOutputBytes: 1024 });
  assert.deepEqual(result, { ok: true, output: 'done' });
});

test('a missing executable is distinguished from a failing one', async () => {
  const result = await runFormatter({ ...spec('gone', ['.x']), command: '/nonexistent/formatter' },
    { absPath: '/tmp/a.x', input: 'x', timeoutMs: 5000, maxOutputBytes: 1024 });
  assert.equal(result.ok, false);
  assert.equal(result.missing, true);
});
