import assert from 'node:assert/strict';
import { existsSync, mkdtempSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { JobManager, describeJob, formatAge } from '../../dotfiles/pi/extensions/job-core.ts';

const manager = (extra = {}) => new JobManager({ shell: ['/bin/sh', '-c'], cwd: tmpdir(), maxJobs: 3, maxBuffer: 1000, ...extra });
const alive = (pid) => { try { process.kill(pid, 0); return true; } catch { return false; } };
const until = async (predicate, ms = 5000) => { const end = Date.now() + ms; while (Date.now() < end) { if (predicate()) return; await new Promise((r) => setTimeout(r, 25)); } throw new Error('timed out'); };

test('a job runs in the background and its output and exit are readable', async () => {
  const jobs = manager();
  const info = jobs.start('echo hello; echo oops >&2; exit 3', 'greeter');
  assert.equal(info.id, 1);
  assert.equal(info.name, 'greeter');
  const read = await jobs.output(1, { waitMs: 5000 });
  await until(() => !jobs.list()[0].running);
  const done = await jobs.output(1);
  assert.match(done.text, /hello/);
  assert.match(done.text, /oops/, 'stderr is kept with stdout');
  assert.equal(done.info.exitCode, 3);
  assert.equal(done.info.running, false);
  assert.match(describeJob(done.info), /^#1 greeter · exit 3 after \d+s$/);
  assert.ok(read.cursor >= 0);
});

test('output with a cursor returns only what is new, and wait blocks for it', async () => {
  const jobs = manager();
  jobs.start('echo one; sleep 0.4; echo two; sleep 0.4; echo three');
  const first = await jobs.output(1, { waitMs: 3000 });
  assert.match(first.text, /one/);
  assert.ok(!first.text.includes('three'));
  const second = await jobs.output(1, { since: first.cursor, waitMs: 3000 });
  assert.ok(second.text.includes('two') && !second.text.includes('one'), second.text);
  const quiet = Date.now();
  const none = await jobs.output(1, { since: second.cursor + 1000, waitMs: 200 });
  assert.equal(none.text, '', 'nothing new yet');
  assert.ok(Date.now() - quiet >= 150, 'the call waited');
  await jobs.stop(1);
});

test('only the newest output is kept, and a reader that fell behind is told how much it missed', async () => {
  const jobs = manager({ maxBuffer: 100 });
  jobs.start("i=0; while [ $i -lt 400 ]; do echo line-$i; i=$((i+1)); done");
  await until(() => !jobs.list()[0].running);
  const all = await jobs.output(1);
  assert.ok(all.text.length <= 100);
  assert.ok(all.text.includes('line-399'));
  assert.ok(all.dropped > 0, 'asking from the start after the buffer rolled over reports what was lost');
  const current = await jobs.output(1, { since: all.cursor });
  assert.equal(current.dropped, 0, 'a reader that is up to date missed nothing');
  assert.equal(current.text, '');
  const tail = await jobs.output(1, { tail: 2 });
  assert.deepEqual(tail.text.trimEnd().split('\n').length <= 2, true);
});

test('a bounded read returns a piece and its cursor continues from the cut', async () => {
  const jobs = manager({ maxBuffer: 10000 });
  jobs.start("i=0; while [ $i -lt 200 ]; do echo line-$i; i=$((i+1)); done");
  await until(() => !jobs.list()[0].running);
  const first = await jobs.output(1, { limit: 50 });
  assert.equal(first.text.length, 50);
  assert.equal(first.truncated, true);
  assert.equal(first.cursor, 50, 'the cursor stops where the text did');
  const second = await jobs.output(1, { since: first.cursor, limit: 50 });
  const joined = first.text + second.text;
  assert.equal(joined, (await jobs.output(1, { limit: 100 })).text, 'two pieces read what one read of both would');
  const rest = await jobs.output(1, { since: 100 });
  assert.equal(rest.truncated, false);
});

test('stop ends the whole process group, including children the command started', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'job-'));
  const jobs = manager();
  jobs.start(`sleep 60 & echo $! > ${dir}/child; echo $$ > ${dir}/shell; wait`);
  await until(() => existsSync(`${dir}/child`) && existsSync(`${dir}/shell`) && readFileSync(`${dir}/child`, 'utf8').trim() !== '');
  const child = Number(readFileSync(`${dir}/child`, 'utf8'));
  assert.ok(alive(child));
  const info = await jobs.stop(1);
  assert.equal(info.running, false);
  assert.equal(info.signal, 'SIGTERM');
  await until(() => !alive(child));
});

test('a command that ignores SIGTERM is killed after the grace period', async () => {
  const jobs = manager();
  jobs.start("trap '' TERM; while true; do sleep 0.1; done");
  await new Promise((r) => setTimeout(r, 200));
  const info = await jobs.stop(1, 300);
  assert.equal(info.running, false);
  assert.equal(info.signal, 'SIGKILL');
});

test('the job limit, unknown ids and empty commands are refused clearly', async () => {
  const jobs = manager({ maxJobs: 2 });
  jobs.start('sleep 5');
  jobs.start('sleep 5');
  assert.throws(() => jobs.start('sleep 5'), /2 jobs are already running/);
  assert.throws(() => jobs.start('   '), /needs a command/);
  await assert.rejects(jobs.output(99), /no job #99/);
  await jobs.stop(1);
  jobs.start('sleep 5');
  assert.equal(jobs.running, 2);
  jobs.stopAll();
  await until(() => jobs.running === 0);
});

test('onExit fires once per job, whatever ended it', async () => {
  const jobs = manager();
  const seen = [];
  jobs.onExit = (info) => seen.push(`${info.id}:${info.exitCode ?? info.signal}`);
  jobs.start('exit 0');
  jobs.start('sleep 30');
  await until(() => seen.length === 1);
  await jobs.stop(2);
  await until(() => seen.length === 2);
  assert.deepEqual(seen.sort(), ['1:0', '2:SIGTERM']);
});

test('formatAge reads well', () => {
  assert.equal(formatAge(4000), '4s');
  assert.equal(formatAge(72000), '1m 12s');
  assert.equal(formatAge(3 * 3600_000 + 5 * 60_000), '3h 5m');
});
