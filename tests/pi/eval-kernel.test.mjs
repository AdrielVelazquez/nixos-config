import test from 'node:test';
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { Kernel } from '../../dotfiles/pi/extensions/eval-kernel.ts';
import { endNotices, reachedTools, toolAnswer } from '../../dotfiles/pi/extensions/eval-core.ts';

const python = process.env.PI_EVAL_PYTHON ?? 'python3';
const runner = resolve('dotfiles/pi/eval/runner.py');
const noTools = async () => ({ ok: false, error: 'no tools in this test' });
const kernels = [];

async function start(options = {}) {
  const cwd = await mkdtemp(join(tmpdir(), 'pi-eval-kernel-'));
  const kernel = new Kernel({ python, runner, cwd, graceMs: 1500, ...options });
  kernels.push(kernel);
  return { kernel, cwd, run: (code, run = {}) => kernel.run(code, { call: noTools, ...run }) };
}
test.after(() => kernels.forEach(kernel => kernel.kill()));

test('variables, functions and imports survive from cell to cell, and a final expression is echoed', async () => {
  const { run } = await start();
  assert.equal((await run('import math\nrate = 3\ndef scale(x):\n    return x * rate')).output, '');
  const second = await run('print("scaled", scale(math.floor(2.5)))\nrate = 10\nscale(2)');
  assert.deepEqual([second.ok, second.output], [true, 'scaled 6\n20\n']);
  assert.equal((await run('scale(1)')).output, '10\n');
});

test('an exception reports the cell\'s own frames and leaves the namespace usable', async () => {
  const { run } = await start();
  await run('kept = [1, 2]');
  const failed = await run('def boom(items):\n    return items[5]\nboom(kept)');
  assert.equal(failed.ok, false);
  assert.match(failed.output, /Traceback \(most recent call last\):/);
  assert.match(failed.output, /File "<eval-2>", line 3, in <module>\n\s+boom\(kept\)/);
  assert.match(failed.output, /IndexError: list index out of range/);
  assert.doesNotMatch(failed.output, /runner\.py|run_cell/);
  assert.equal((await run('len(kept)')).output, '2\n');
  const syntax = await run('def broken(:');
  assert.equal(syntax.ok, false);
  assert.match(syntax.output, /SyntaxError/);
  const exit = await run('raise SystemExit(3)');
  assert.deepEqual([exit.ok, exit.died, /SystemExit\(3\)/.test(exit.output)], [false, false, true]);
  assert.equal((await run('kept')).output, '[1, 2]\n');
});

test('stdout, stderr and child processes arrive in the order they were written', async () => {
  const { run } = await start();
  const result = await run('import os, subprocess, sys\nprint("one", flush=True)\nos.system("echo two")\nprint("three", file=sys.stderr, flush=True)\nsubprocess.run(["echo", "four"])\nprint("five")');
  assert.equal(result.output, 'one\ntwo\nthree\nfour\nfive\n');
});

test('a cell cannot read the control channel, and children inherit neither it nor a stdin', async () => {
  const { run } = await start();
  const children = await run('import subprocess\nprint(subprocess.run(["sh", "-c", "ls /proc/self/fd"], capture_output=True, text=True).stdout.split())\nprint(subprocess.run(["sh", "-c", "cat"], capture_output=True, text=True, timeout=5).stdout == "")');
  assert.match(children.output, /^\['0', '1', '2', '\d'\]\nTrue\n$/);
  const input = await run('input()');
  assert.match(input.output, /EOFError/);
});

test('output that looks like the end marker, and large output, arrive intact', async () => {
  const { run } = await start();
  const tricky = await run('print("\\0PIEVAL-0000-1\\0 not a marker")\nprint("\\0PIEVAL")');
  assert.equal(tricky.output, '\0PIEVAL-0000-1\0 not a marker\n\0PIEVAL\n');
  const big = await run('print("x" * 3_000_000)\nprint("end")');
  assert.equal(big.output.length, 3_000_000 + 1 + 4);
  assert.equal(big.output.endsWith('xend\n'), false);
  assert.equal(big.output.endsWith('x\nend\n'), true);
});

test('a timeout interrupts the cell and keeps the namespace; a cell that ignores the interrupt is killed', async () => {
  const { kernel, run } = await start();
  await run('survivor = 41');
  const slow = await run('import time\nwhile True:\n    time.sleep(0.01)', { timeoutMs: 400 });
  assert.deepEqual([slow.ok, slow.timedOut, slow.died], [false, true, false]);
  assert.match(slow.output, /KeyboardInterrupt/);
  assert.equal((await run('survivor + 1')).output, '42\n');
  const stubborn = await run('import signal\nsignal.signal(signal.SIGINT, signal.SIG_IGN)\nwhile True:\n    pass', { timeoutMs: 300 });
  assert.deepEqual([stubborn.timedOut, stubborn.died], [true, true]);
  assert.match(stubborn.exit, /SIGKILL/);
  assert.equal(kernel.alive, false);
});

test('cancelling stops the cell, including a child process it started', async () => {
  const { run, cwd } = await start();
  const controller = new AbortController();
  const marker = join(cwd, 'child-finished');
  const pending = run(`import subprocess\nsubprocess.run(["sh", "-c", "sleep 20; touch ${marker}"])`, { signal: controller.signal });
  setTimeout(() => controller.abort(), 300);
  const result = await pending;
  assert.deepEqual([result.ok, result.cancelled, result.died], [false, true, false]);
  assert.equal((await run('"alive"')).output, "'alive'\n");
  await new Promise(done => setTimeout(done, 400));
  await assert.rejects(import('node:fs/promises').then(fs => fs.access(marker)));
  const before = await run('1', { signal: AbortSignal.abort() });
  assert.deepEqual([before.cancelled, before.output], [true, '']);
});

test('a kernel does not outlive a host that was killed, even in the middle of a cell', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'pi-eval-orphan-'));
  const pidFile = join(dir, 'pid');
  const host = [
    "const { Kernel } = await import(process.env.KERNEL_TS);",
    "const kernel = new Kernel({ python: process.env.PYTHON, runner: process.env.RUNNER, cwd: process.env.DIR });",
    "const code = \"import os\\nopen(os.environ['PID_FILE'], 'w').write(str(os.getpid()))\\nwhile True:\\n    pass\";",
    "kernel.run(code, { call: async () => ({ ok: false, error: 'none' }) });",
    "setTimeout(() => process.kill(process.pid, 'SIGKILL'), 700);",
  ].join('\n');
  const env = { ...process.env, KERNEL_TS: resolve('dotfiles/pi/extensions/eval-kernel.ts'), PYTHON: python, RUNNER: runner, DIR: dir, PID_FILE: pidFile };
  const child = spawn(process.execPath, ['--input-type=module', '-e', host], { env, stdio: 'inherit' });
  await new Promise(done => child.on('exit', done));
  const pid = Number(await readFile(pidFile, 'utf8'));
  let gone = false;
  for (let attempt = 0; attempt < 30 && !gone; attempt++) {
    try { process.kill(pid, 0); await new Promise(done => setTimeout(done, 100)); } catch { gone = true; }
  }
  if (!gone) process.kill(pid, 'SIGKILL');
  assert.equal(gone, true, 'the busy kernel kept running after its host died');
});

test('output past the limit interrupts the cell instead of growing without bound', async () => {
  const { run } = await start({ maxOutputBytes: 200_000 });
  const noisy = await run('import time\nwhile True:\n    print("y" * 1000)\n    time.sleep(0.0005)');
  assert.deepEqual([noisy.ok, noisy.overflow, noisy.died], [false, true, false]);
  assert.equal((await run('"fine"')).output, "'fine'\n");
});

test('a cell calls the session\'s tools; a failed call raises ToolError and write() goes through the write tool', async () => {
  const calls = [];
  const call = async (name, args, signal) => {
    calls.push({ name, args });
    if (name === 'echo') return { ok: true, value: { seen: args } };
    if (name === 'write') return { ok: true, value: `Wrote ${args.path}` };
    if (name === 'slow') return new Promise(resolveCall => signal.addEventListener('abort', () => resolveCall({ ok: false, error: 'aborted' })));
    return { ok: false, error: `no tool ${name}` };
  };
  const { run } = await start();
  const first = await run('print(tool.echo(a=1, b=[2]))\nprint(tool["echo"]({"c": 3}))\nprint(write("out.txt", "hi"))', { call });
  assert.equal(first.output, "{'seen': {'a': 1, 'b': [2]}}\n{'seen': {'c': 3}}\nWrote out.txt\n");
  assert.equal(first.toolCalls, 3);
  assert.deepEqual(calls.at(-1), { name: 'write', args: { path: 'out.txt', content: 'hi' } });
  const failed = await run('try:\n    tool.missing(x=1)\nexcept ToolError as error:\n    print("caught", error)', { call });
  assert.equal(failed.output, 'caught no tool missing\n');
  const timed = await run('tool.slow()', { call, timeoutMs: 300 });
  assert.deepEqual([timed.timedOut, timed.died], [true, false]);
  assert.match(timed.output, /KeyboardInterrupt|ToolError/);
});

test('read() returns raw text for a line window, image() attaches a PNG, state() lists what the cells defined', async () => {
  const { run, cwd } = await start();
  await writeFile(join(cwd, 'lines.txt'), 'a\nb\nc\nd\n');
  const window = await run('print(repr(read("lines.txt", offset=2, limit=2)))\nprint(repr(read("lines.txt")))');
  assert.equal(window.output, "'b\\nc\\n'\n'a\\nb\\nc\\nd\\n'\n");
  const png = 'iVBORw0KGgo=';
  const shown = await run(`import base64\nimage(base64.b64decode("${png}"))`);
  assert.deepEqual(shown.images, [{ type: 'image', data: png, mimeType: 'image/png' }]);
  await run('total = 12\nnames = ["a", "b"]');
  const listed = await run('state()');
  assert.equal(listed.output, "total: int = 12\nnames: list = ['a', 'b']\nimports: base64\n");
});

test('which tools a cell may reach is read from its source, and a bare `tool` reaches them all', () => {
  assert.deepEqual(reachedTools('tool.read(path="a")\ntool["mcp__x__y"](n=1)\nwrite("f", "c")').sort(), ['mcp__x__y', 'read', 'write']);
  assert.deepEqual(reachedTools('print(1 + 1)'), []);
  for (const code of ['t = tool\nt.read()', 'getattr(tool, name)()', 'tool[name]()', 'dir(tool)']) assert.equal(reachedTools(code), 'all', code);
  assert.deepEqual(reachedTools('tool_name = 1'), []);
});

test('a tool result becomes text, a structured value, or parts; a failed one becomes an error', () => {
  const text = { type: 'text', text: 'one' };
  const img = { type: 'image', data: 'AAAA', mimeType: 'image/png' };
  assert.deepEqual(toolAnswer({ isError: false, result: { content: [text, { type: 'text', text: 'two' }] } }), { ok: true, value: 'one\ntwo' });
  assert.deepEqual(toolAnswer({ isError: false, result: { content: [text], structuredContent: { n: 1 } } }), { ok: true, value: { n: 1 } });
  assert.deepEqual(toolAnswer({ isError: false, result: { content: [img] } }), { ok: true, value: [img] });
  assert.deepEqual(toolAnswer({ isError: true, result: { content: [text] } }), { ok: false, error: 'one' });
  assert.deepEqual(toolAnswer({ isError: true }), { ok: false, error: 'the tool failed' });
});

test('the end of a cell that did not simply finish is described', () => {
  const base = { ok: false, output: '', images: [], timedOut: false, cancelled: false, died: false, overflow: false, toolCalls: 0 };
  assert.deepEqual(endNotices({ ...base, timedOut: true }, 120, 64), ['The cell timed out after 120s and was interrupted.']);
  assert.match(endNotices({ ...base, died: true, exit: 'killed by SIGKILL' }, undefined, 64)[0], /variables are gone/);
  assert.deepEqual(endNotices({ ...base, ok: true }, undefined, 64), []);
});
