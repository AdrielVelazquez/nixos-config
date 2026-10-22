import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRouting } from '../../dotfiles/pi/extensions/routing.ts';

const agents = { build: { model: 'work/sol', thinking: 'high' }, plan: { model: 'work/sonnet', thinking: 'xhigh' },
  title: { model: 'work/luna', thinking: 'low' } };
function fixture() {
  const handlers = new Map(), commands = new Map(), changes = [], entries = [];
  const models = new Map(['sol', 'sonnet', 'luna'].map(id => [id, { provider: 'work', id, reasoning: true }]));
  let thinking = 'high', name;
  const ctx = { model: models.get('sol'), ui: { notify() {}, setStatus() {} },
    sessionManager: { getSessionId: () => 'parent', getSessionName: () => name, getBranch: () => entries },
    modelRegistry: { find: (provider, id) => provider === 'work' ? models.get(id) : undefined,
      streamSimple: (model, context, options) => {
        changes.push({ title: model.id, context, options });
        return { result: async () => ({ stopReason: 'stop', content: [{ type: 'text', text: 'A useful title' }] }) };
      } } };
  const pi = { on: (event, fn) => handlers.set(event, fn), registerCommand: (name, command) => commands.set(name, command),
    setModel: async model => { changes.push({ model: model.id }); ctx.model = model; return true; },
    setThinkingLevel: level => { changes.push({ thinking: level }); thinking = level; }, getThinkingLevel: () => thinking,
    appendEntry: (customType, data) => entries.push({ type: 'custom', customType, data }),
    setSessionName: value => { name = value; } };
  createRouting(pi, { agents, autoTitle: true });
  return { ctx, pi, handlers, commands, changes, entries, models, get name() { return name; } };
}
test('explicit primary mode selects the exact provider/model and thinking', async () => {
  const f = fixture(); await f.commands.get('plan').handler('', f.ctx);
  assert.deepEqual(f.changes, [{ model: 'sonnet' }, { thinking: 'xhigh' }]);
  await f.commands.get('build').handler('', f.ctx);
  assert.deepEqual(f.changes.slice(-2), [{ model: 'sol' }, { thinking: 'high' }]);
  assert.equal(f.entries.at(-1).data.mode, 'build');
});
test('a missing exact target fails without substituting an available model', async () => {
  const f = fixture(); f.models.delete('sonnet');
  await assert.rejects(f.commands.get('plan').handler('', f.ctx), /not available|unknown/i);
  assert.deepEqual(f.changes, []);
});
test('reload/resume preserves a deliberately selected native model and mode', async () => {
  const f = fixture(); await f.commands.get('plan').handler('', f.ctx);
  f.ctx.model = f.models.get('luna'); f.changes.length = 0;
  await f.handlers.get('session_start')({ reason: 'resume' }, f.ctx);
  assert.deepEqual(f.changes, []);
  assert.match((await f.handlers.get('before_agent_start')({ systemPrompt: 'BASE' }, f.ctx)).systemPrompt, /plan/);
  assert.equal(f.handlers.has('session_before_compact'), false, 'compaction must remain on the native session model');
});
test('unsupported thinking is rejected before changing the primary model', async () => {
  const f = fixture(); f.models.get('sonnet').thinkingLevelMap = { xhigh: null };
  await assert.rejects(f.commands.get('plan').handler('', f.ctx), /thinking|xhigh/i);
  assert.deepEqual(f.changes, []);
});
test('auxiliary titles use the exact cheap target without changing session model or thinking', async () => {
  const f = fixture(); f.entries.push({ type: 'message', message: { role: 'user', content: 'Help debug a small fixture' } });
  await f.handlers.get('agent_end')({ messages: [{ role: 'assistant', stopReason: 'stop' }] }, f.ctx);
  assert.equal(f.name, 'A useful title');
  assert.equal(f.changes.length, 1); assert.equal(f.changes[0].title, 'luna'); assert.equal(f.changes[0].options.reasoning, 'low');
  assert.equal(f.ctx.model.id, 'sol');
});
