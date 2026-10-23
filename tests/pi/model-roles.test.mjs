import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, readFileSync, statSync, symlinkSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
const host = process.env.PI_TEST_PACKAGE_DIR;
assert.ok(host, 'PI_TEST_PACKAGE_DIR must identify real Pi');
const { createJiti } = await import(pathToFileURL(`${host}/node_modules/jiti/lib/jiti.mjs`));
const jiti = createJiti(import.meta.url, { alias: {
  '@earendil-works/pi-coding-agent': `${host}/dist/index.js`,
  '@earendil-works/pi-tui': `${host}/node_modules/@earendil-works/pi-tui/dist/index.js`,
} });
const { createModelRoles, parseConfig } = await jiti.import(resolve('dotfiles/pi/extensions/model-roles.ts'));
const dirs = [];
function fixture(options = {}, flags = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'pi-model-roles-')); dirs.push(dir);
  process.env.PI_CODING_AGENT_DIR = dir;
  const handlers = new Map(), commands = new Map(), shortcuts = new Map(), virtual = new Map(), warnings = [], entries = [], calls = [];
  let tools = ['read', 'write', 'bash', 'question', 'ast_grep_run', 'fetch_content'];
  const models = ['primary', 'small', 'strong'].map(id => ({ provider: 'fixture', id, input: ['text'], reasoning: true }));
  const ctx = { mode: 'tui', hasUI: true, ui: { notify: (...args) => warnings.push(args), setStatus() {}, setWidget() {} },
    sessionManager: { getBranch: () => entries, getSessionId: () => 'parent', getSessionName: () => undefined },
    modelRegistry: { getAvailable: () => models, find: (p, id) => p === 'roles' ? { provider: p, id } : models.find(m => m.provider === p && m.id === id),
      streamSimple: (model, context, options) => { calls.push({ model, context, options }); return { result: async () => ({ stopReason: 'stop', content: [{ type: 'text', text: 'Useful result' }] }) }; } } };
  const pi = { on: (name, fn) => handlers.set(name, fn), registerCommand: (name, command) => commands.set(name, command), registerFlag() {}, getFlag: name => flags[name],
    registerVirtualModel: value => virtual.set(value.id, value), registerShortcut: (name, value) => shortcuts.set(name, value),
    getThinkingLevel: () => 'high', getActiveTools: () => [...tools], setActiveTools: value => { tools = value; }, setModel: async () => true,
    appendEntry: (customType, data) => entries.push({ type: 'custom', customType, data }), sendUserMessage() {}, sendMessage() {}, setSessionName() {} };
  createModelRoles(pi, { modelRoles: { default: 'fixture/primary:high', smol: 'fixture/small:low', slow: 'fixture/strong:high', plan: '@slow', tiny: '@smol' }, autoTitle: false, ...options });
  return { dir, ctx, pi, handlers, commands, shortcuts, virtual, warnings, entries, calls, get tools() { return tools; } };
}
test('factory wires every real consumer, flags and non-conflicting shortcut', () => {
  const f = fixture();
  for (const name of ['models', 'role', 'use-role', 'plan', 'slow', 'build', 'commit', 'advisor', 'memory', 'widget', 'role-agents']) assert.ok(f.commands.has(name), name);
  assert.ok(f.shortcuts.has('ctrl+shift+u')); assert.ok(f.virtual.has('auto'));
});
test('plan defaults soft; build returns default role', async () => {
  const f = fixture(); await f.handlers.get('session_start')({}, f.ctx);
  const before = f.tools;
  await f.commands.get('plan').handler('', f.ctx); assert.deepEqual(f.tools, before);
  assert.equal(f.handlers.get('tool_call')({ toolName: 'write' }, f.ctx), undefined);
  assert.match(f.handlers.get('before_agent_start')({ systemPrompt: 'BASE' }, f.ctx).systemPrompt, /planning/i);
  assert.equal(f.virtual.get('auto').route({ reason: 'user' }, f.ctx).model.id, 'strong');
  await f.commands.get('build').handler('', f.ctx);
  assert.equal(f.virtual.get('auto').route({ reason: 'user' }, f.ctx).model.id, 'primary');
});
test('explicit read-only plan allows question, ast and fetch reads and restores tools on shutdown', async () => {
  const f = fixture({ planMode: { readOnly: true } }); await f.handlers.get('session_start')({}, f.ctx);
  const before = f.tools; await f.commands.get('plan').handler('', f.ctx);
  assert.deepEqual(f.tools, ['read', 'question', 'ast_grep_run', 'fetch_content']);
  assert.equal(f.handlers.get('tool_call')({ toolName: 'write' }, f.ctx).block, true);
  await f.handlers.get('session_shutdown')({}, f.ctx); assert.deepEqual(f.tools, before);
});
test('CLI flag is process-only; validated role edit writes private overlay, not defaults', async () => {
  const f = fixture({}, { smol: 'fixture/strong:off' }); await f.handlers.get('session_start')({}, f.ctx);
  assert.equal(f.virtual.get('smol').route({ reason: 'user' }, f.ctx).model.id, 'strong');
  await f.commands.get('role').handler('research fixture/small:low', f.ctx);
  const path = join(f.dir, 'model-roles.user.json');
  assert.equal(statSync(path).mode & 0o777, 0o600);
  assert.deepEqual(JSON.parse(readFileSync(path)), { modelRoles: { research: 'fixture/small:low' } });
  await assert.rejects(f.commands.get('role').handler('research @research', f.ctx), /cycle/);
});
test('invalid overlay is ignored once without losing immutable defaults across reload', async () => {
  const f = fixture(); writeFileSync(join(f.dir, 'model-roles.user.json'), JSON.stringify({ modelRoles: { default: 'bad:auto' } }));
  await f.handlers.get('session_start')({}, f.ctx); await f.handlers.get('session_start')({}, f.ctx);
  assert.equal(f.warnings.length, 1);
  assert.match(f.warnings[0][0], /overlay.*ignored/i);
  assert.equal(f.virtual.get('auto').route({ reason: 'user' }, f.ctx).model.id, 'primary');
});
test('overlay parser rejects malformed selectors and unsupported settings', () => {
  for (const value of [{ modelRoles: { a: 'fixture/nope:auto' } }, { retry: { fallbackChains: { default: [7] } } }, { cycleOrder: ['bad role'] }, { autoTitle: 'yes' }, { compactionRole: 3 }]) assert.throws(() => parseConfig(JSON.stringify(value)));
});
test('task export never writes through managed agent symlinks', async () => {
  const f = fixture({ agents: { build: { description: 'Build', prompt: 'Build.' } } });
  const { mkdirSync } = await import('node:fs'); mkdirSync(join(f.dir, 'agents'));
  const managed = join(f.dir, 'immutable.md'); writeFileSync(managed, 'MANAGED'); symlinkSync(managed, join(f.dir, 'agents/build.md'));
  await f.handlers.get('session_start')({}, f.ctx); await f.commands.get('role-agents').handler('', f.ctx);
  assert.equal(readFileSync(managed, 'utf8'), 'MANAGED');
  assert.match(readFileSync(join(f.dir, 'model-roles-agents/build.md'), 'utf8'), /model: "fixture\/primary"/);
});
test.after(() => { for (const dir of dirs) rmSync(dir, { recursive: true, force: true }); });
test('cyclic overlay is ignored atomically with one warning', async () => {
  const f = fixture(); writeFileSync(join(f.dir, 'model-roles.user.json'), JSON.stringify({ modelRoles: { default: '@loop', loop: '@default' } }));
  await f.handlers.get('session_start')({}, f.ctx);
  assert.equal(f.warnings.length, 1);
  assert.equal(f.virtual.get('auto').route({ reason: 'user' }, f.ctx).model.id, 'primary');
});
test('models command is harmless in headless mode', async () => {
  const f = fixture(); f.ctx.hasUI = false;
  await f.handlers.get('session_start')({}, f.ctx);
  await f.commands.get('models').handler('', f.ctx);
  assert.match(f.warnings.at(-1)[0], /interactive|TUI/i);
});
test('auxiliary commands consume their assigned models without changing conversation mode', async () => {
  const f = fixture({ modelRoles: { default: 'fixture/primary:high', smol: 'fixture/small:low', advisor: 'fixture/strong:high' } });
  await f.handlers.get('session_start')({}, f.ctx);
  for (const role of ['commit', 'advisor', 'memory', 'widget']) await f.commands.get(role).handler('Explicit task', f.ctx);
  assert.deepEqual(f.calls.map(call => call.model.id), ['small', 'strong', 'small', 'small']);
  assert.equal(f.virtual.get('auto').route({ reason: 'user' }, f.ctx).model.id, 'primary');
  assert.equal(JSON.parse(readFileSync(join(f.dir, 'model-roles.memory.json'))).notes, 'Useful result');
  assert.equal(statSync(join(f.dir, 'model-roles.memory.json')).mode & 0o777, 0o600);
});
test('automatic title consumes tiny without changing the native selected model', async () => {
  const f = fixture({ autoTitle: true });
  f.entries.push({ type: 'message', message: { role: 'user', content: 'Task' } });
  await f.handlers.get('session_start')({}, f.ctx);
  await f.handlers.get('agent_end')({ messages: [{ role: 'assistant', stopReason: 'stop' }] }, f.ctx);
  assert.equal(f.calls.length, 1); assert.equal(f.calls[0].model.id, 'small');
  assert.equal(f.calls[0].options.reasoning, 'low');
});
