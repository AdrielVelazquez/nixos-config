import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { tmpdir } from 'node:os';
import { resolve } from 'node:path';
import test from 'node:test';

const sdk = process.env.PI_TEST_PACKAGE_DIR;
const require = createRequire(`${sdk}/package.json`);
const { createJiti } = require('jiti');
const jiti = createJiti(import.meta.url, { alias: {
  '@earendil-works/pi-coding-agent': `${sdk}/dist/index.js`,
  '@earendil-works/pi-tui': `${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`,
  '@earendil-works/pi-ai': `${sdk}/node_modules/@earendil-works/pi-ai/dist/index.js`,
  typebox: `${sdk}/node_modules/typebox/build/index.mjs`,
} });
const { createJobs } = await jiti.import(resolve('dotfiles/pi/extensions/job.ts'));

function host(extra = {}) {
  const handlers = new Map(), commands = new Map();
  let tool;
  const log = { statuses: [], notices: [] };
  const pi = { on: (name, handler) => handlers.set(name, handler), registerTool: (definition) => { tool = definition; }, registerCommand: (name, spec) => commands.set(name, spec.handler) };
  const ctx = { cwd: tmpdir(), hasUI: true, ui: { setStatus: (key, text) => log.statuses.push([key, text]), notify: (message, kind) => log.notices.push([kind, message]) } };
  createJobs(pi, { shell: ['/bin/sh', '-c'], cwd: tmpdir(), maxJobs: 2, maxBuffer: 10000, notifyOnExit: true, ...extra });
  const call = (params) => tool.execute('id', params, undefined, undefined, ctx).then((result) => result.content[0].text);
  return { handlers, commands, log, ctx, call, tool };
}

const until = async (predicate, ms = 5000) => { const end = Date.now() + ms; while (Date.now() < end) { if (predicate()) return; await new Promise((r) => setTimeout(r, 25)); } throw new Error('timed out'); };

test('start, list, output and stop work through the tool and keep the footer status', async () => {
  const h = host();
  assert.equal(h.tool.name, 'job');
  const started = await h.call({ op: 'start', command: 'echo ready; sleep 30', name: 'server' });
  assert.match(started, /^Started #1 server · running/);
  assert.deepEqual(h.log.statuses.at(-1), ['jobs', 'jobs 1']);
  const out = await h.call({ op: 'output', id: 1, wait: 5 });
  assert.match(out, /#1 server · running/);
  assert.match(out, /cursor: \d+/);
  assert.match(out, /---\nready/);
  const cursor = Number(/cursor: (\d+)/.exec(out)[1]);
  assert.match(await h.call({ op: 'output', id: 1, since: cursor }), /\(no new output\)/);
  assert.match(await h.call({ op: 'list' }), /#1 server · running/);
  assert.match(await h.call({ op: 'stop', id: 1 }), /Stopped #1 server · killed by SIGTERM/);
  assert.deepEqual(h.log.statuses.at(-1), ['jobs', undefined], 'the status clears when nothing runs');
  assert.match(await h.call({ op: 'list' }), /killed by SIGTERM/);
});

test('a finished job is announced once and bad requests fail with a reason', async () => {
  const h = host();
  await h.call({ op: 'start', command: 'exit 2', name: 'failing' });
  await until(() => h.log.notices.length === 1);
  assert.equal(h.log.notices[0][0], 'warning');
  assert.match(h.log.notices[0][1], /Job #1 failing · exit 2/);
  await assert.rejects(h.call({ op: 'start' }), /needs a `command`/);
  await assert.rejects(h.call({ op: 'output' }), /needs the job `id`/);
  await assert.rejects(h.call({ op: 'stop', id: 7 }), /no job #7/);
});

test('/jobs lists and stops, and the session end kills what still runs', async () => {
  const h = host();
  await h.call({ op: 'start', command: 'sleep 30', name: 'one' });
  await h.call({ op: 'start', command: 'sleep 30', name: 'two' });
  await h.call({ op: 'start', command: 'sleep 30' }).then(() => assert.fail('the third job should be refused'), (error) => assert.match(error.message, /2 jobs are already running/));
  await h.commands.get('jobs')('', h.ctx);
  assert.match(h.log.notices.at(-1)[1], /#1 one · running[\s\S]*#2 two · running/);
  await h.commands.get('jobs')('stop 1', h.ctx);
  assert.match(h.log.notices.at(-1)[1], /Stopped 1 job$/);
  await h.commands.get('jobs')('stop nonsense', h.ctx);
  assert.match(h.log.notices.at(-1)[1], /Usage: \/jobs stop/);
  await h.commands.get('jobs')('stop all', h.ctx);
  assert.match(h.log.notices.at(-1)[1], /Stopped 1 job$/);
  const started = await h.call({ op: 'start', command: 'sleep 30' });
  const pid = Number(/pid (\d+)/.exec(started)[1]);
  const alive = () => { try { process.kill(pid, 0); return true; } catch { return false; } };
  assert.ok(alive());
  h.handlers.get('session_shutdown')({}, h.ctx);
  assert.deepEqual(h.log.statuses.at(-1), ['jobs', undefined]);
  await until(() => !alive());
  const announced = h.log.notices.length;
  await new Promise((r) => setTimeout(r, 200));
  assert.equal(h.log.notices.length, announced, 'a job killed by the session ending is not announced to a context that is gone');
});

test('a stale context after the session ends never crashes an exiting job', async () => {
  const h = host();
  await h.call({ op: 'start', command: 'sleep 0.3', name: 'late' });
  Object.defineProperty(h.ctx, 'hasUI', { get() { throw new Error('This extension ctx is stale after session replacement or reload.'); } });
  await new Promise((r) => setTimeout(r, 700));
  assert.ok(true, 'the exit callback swallowed the stale context instead of throwing');
});
