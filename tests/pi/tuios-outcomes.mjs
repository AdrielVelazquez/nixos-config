import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createTuiosOutcomes } from '../../dotfiles/pi/extensions/tuios-outcomes.ts';

function fixture(mode = 'tui', child = false) {
  process.env.TUIOS_PANE_ID = 'synthetic-pane'; process.env.TUIOS_ENV = '1';
  if (child) process.env.PI_SUBAGENT_CHILD = '1'; else delete process.env.PI_SUBAGENT_CHILD;
  const handlers = new Map(), calls = [];
  const ctx = { mode, isIdle: () => true, sessionManager: { getSessionId: () => 'synthetic-session', getBranch: () => [] } };
  const pi = { on: (event, fn) => handlers.set(event, fn), exec: async (binary, args) => {
    calls.push({ binary, args }); return { code: 0, stderr: '', stdout: '' };
  } };
  createTuiosOutcomes(pi, '/synthetic/tuios');
  return { handlers, calls, ctx, pi };
}
async function settled(f, reason) {
  await f.handlers.get('session_start')({}, f.ctx);
  await f.handlers.get('agent_start')({}, f.ctx);
  await f.handlers.get('message_end')({ message: { role: 'assistant', stopReason: reason } }, f.ctx);
  await f.handlers.get('agent_settled')({}, f.ctx);
}
test('failed turns correct only the same pane/session after upstream reports done', async () => {
  const f = fixture(); await settled(f, 'error');
  assert.equal(f.calls.length, 1);
  assert.equal(f.calls[0].binary, '/synthetic/tuios');
  assert.deepEqual(f.calls[0].args.slice(0, 4), ['set-agent-state', 'errored', '--if-state', 'done']);
  assert.ok(f.calls[0].args.includes('synthetic-pane') && f.calls[0].args.includes('synthetic-session'));
});
test('successful/recovered turns do not overwrite upstream completion', async () => {
  const f = fixture(); await settled(f, 'stop'); assert.deepEqual(f.calls, []);
});
test('interruption reports errored rather than successful completion', async () => {
  const f = fixture(); await settled(f, 'aborted'); assert.ok(f.calls[0].args.includes('Interrupted'));
});
test('settlement cancellation after a successful response still reports interrupted', async () => {
  const f = fixture();
  await f.handlers.get('session_start')({}, f.ctx);
  await f.handlers.get('agent_start')({}, f.ctx);
  await f.handlers.get('message_end')({ message: { role: 'assistant', stopReason: 'stop' } }, f.ctx);
  await f.handlers.get('agent_settled')({ aborted: true }, f.ctx);
  assert.equal(f.calls.length, 1);
  assert.ok(f.calls[0].args.includes('Interrupted'));
});
test('child and non-TUI sessions never claim the parent pane', async () => {
  for (const f of [fixture('rpc'), fixture('tui', true)]) { await settled(f, 'error'); assert.deepEqual(f.calls, []); }
});
test('a delayed upstream done report is retried conditionally, never forced onto working', async () => {
  const f = fixture(); let count = 0;
  f.pi.exec = async (_binary, args) => { f.calls.push(args); return { code: 0, stderr: ++count === 1 ? 'Not applied: condition not met. It still reports working.' : '' }; };
  await settled(f, 'error'); assert.equal(f.calls.length, 2);
  assert.ok(f.calls.every(args => args.includes('--if-state') && args.includes('done')));
});
