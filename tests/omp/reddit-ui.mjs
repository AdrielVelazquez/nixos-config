import assert from 'node:assert/strict';
import { test } from 'node:test';
import { registerReddit } from '../../dotfiles/omp/reddit-ui.ts';

function fixture() {
  const commands = new Map(), outputs = [], edits = [], calls = [], answers = [];
  const pi = { registerCommand: (name, value) => commands.set(name, value), getThinkingLevel: () => 'high', on() {} };
  const ctx = { agent: { kind: 'main' }, cwd: '/fixture', hasUI: true, mode: 'tui', model: { provider: 'llmplatform', id: 'fixture/model' },
    ui: { select: async () => answers.shift(), input: async () => answers.shift(), confirm: async () => answers.shift(),
      setEditorText: value => edits.push(value), notify: (text, level) => outputs.push({ text, level }) } };
  const services = {
    status: () => ({ project: { id: 'alpha-project', source: 'directory', locked: false },
      model: { provider: 'llmplatform', id: 'fixture/model' }, catalog: { status: 'ready', count: 3 },
      transport: { required: true, configured: true, proxyURL: 'http://127.0.0.1:19999' } }),
    quota: async () => { calls.push('quota'); return { reading: { status: 'ready' }, text: 'Used: $1.00\nRemaining: $4.00' }; },
    refreshModels: async () => calls.push('refresh'),
    projectChoices: async () => ({ configured: { id: 'opencode-dev', source: 'default', locked: false }, saved: ['beta-project'] }),
    previewProject: async id => { calls.push('preview:' + id); return { id, models: [{ id: 'fixture/model', name: 'Fixture' }] }; },
    commitProject: async (value, _ctx, id) => { calls.push('commit:' + value.id + ':' + id); return { project: { id: value.id }, saved: true }; },
  };
  const tools = { snapshot: async () => ({ configured: false, connection: 'not configured', providers: [] }),
    setup: async () => { calls.push('setup'); return true; }, signIn: async () => calls.push('login'),
    signOut: async () => calls.push('logout'), refresh: async () => calls.push('tools-refresh'),
    showConnection: async () => calls.push('details'), setProviderEnabled: async (_ctx, id, enabled) => calls.push(id + ':' + enabled) };
  registerReddit(pi, { services, tools, writeOutput: (_ctx, text, level) => outputs.push({ text, level }) });
  return { commands, outputs, edits, calls, answers, ctx, services, tools,
    run: (args, context = ctx, name = 'reddit') => commands.get(name).handler(args, context) };
}

test('reddit is a native command with status and compatibility alias, not a model prompt', async () => {
  const f = fixture();
  assert.ok(f.commands.has('reddit'));
  await f.run('status');
  const text = f.outputs.at(-1).text;
  assert.match(text, /alpha-project/); assert.match(text, /fixture\/model/); assert.match(text, /high/);
  assert.match(text, /3/); assert.match(text, /Headroom|required/i); assert.match(text, /not configured/);
  assert.ok(!text.includes('Bearer'));
  await f.run('refresh', f.ctx, 'llmplatform');
  assert.deepEqual(f.calls, ['refresh']);
});

test('menu, model handoff and quota use native UI without inference', async () => {
  const f = fixture();
  f.answers.push('Model status'); await f.run('');
  assert.match(f.outputs.at(-1).text, /alpha-project/);
  await f.run('model'); assert.equal(f.edits.at(-1), '/model');
  f.answers.push('Back'); await f.run('quota');
  assert.deepEqual(f.calls, ['quota']);
});

test('project selection preflights and requires explicit confirmation before native commit', async () => {
  const f = fixture();
  f.answers.push(false); await f.run('project beta-project');
  assert.deepEqual(f.calls, ['preview:beta-project']);
  f.answers.push(true); await f.run('project beta-project');
  assert.equal(f.calls.at(-1), 'commit:beta-project:fixture/model');
});

test('headless diagnostics are readable and interactive/worker mutations cannot run', async () => {
  const f = fixture();
  const print = { ...f.ctx, mode: 'print', hasUI: false };
  await f.run('status', print); assert.match(f.outputs.at(-1).text, /alpha-project/);
  await f.run('project beta-project', print); assert.match(f.outputs.at(-1).text, /interactive|UI/i);
  await f.run('tools setup', print); assert.match(f.outputs.at(-1).text, /interactive|UI/i);
  await f.run('tools login', { ...f.ctx, agent: { kind: 'sub' } }); assert.match(f.outputs.at(-1).text, /main.session/i);
  assert.deepEqual(f.calls, []);
});

test('tool controls delegate to the real controller and cancellation does not sign in', async () => {
  const f = fixture();
  await f.run('tools setup'); assert.deepEqual(f.calls, ['setup', 'login']);
  f.tools.setup = async () => false;
  await f.run('tools setup'); assert.deepEqual(f.calls, ['setup', 'login']);
  await f.run('tools logout'); assert.equal(f.calls.at(-1), 'logout');
});
