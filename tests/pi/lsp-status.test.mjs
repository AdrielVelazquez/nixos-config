import assert from 'node:assert/strict';
import test from 'node:test';
import { existsSync, readFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve } from 'node:path';

const source = resolve(process.env.LSP_STATUS_SOURCE ?? 'dotfiles/pi/extensions/lsp-status.ts');
async function install(upstream, options) {
  assert.ok(existsSync(source), 'the composable LSP status bridge exists');
  const { createLspStatus } = await import(pathToFileURL(source));
  const events = new Map();
  const statuses = [];
  let footerCalls = 0;
  const pi = {
    registerTool() {},
    on(name, callback) { const list = events.get(name) ?? []; list.push(callback); events.set(name, list); },
  };
  const ctx = { ui: { setStatus: (...args) => statuses.push(args), setFooter: () => footerCalls++ } };
  createLspStatus(pi, upstream, options);
  return { statuses, get footerCalls() { return footerCalls; }, async emit(name) { for (const handler of events.get(name) ?? []) await handler({}, ctx); } };
}
const upstream = rows => pi => pi.registerTool({ name: 'lsp_status', async execute() { return { structuredContent: { servers: rows } }; } });

test('captures status without replacing the footer', async () => {
  const app = await install(upstream([{ server_id: 'gopls', state: 'running' }, { server_id: 'typescript', state: 'running' }]));
  for (const event of ['session_start', 'tool_result', 'agent_end']) await app.emit(event);
  assert.deepEqual(app.statuses, Array(3).fill(['lsp', 'LSP gopls ● · typescript ●']));
  assert.equal(app.footerCalls, 0);
  await app.emit('session_shutdown');
  assert.deepEqual(app.statuses.at(-1), ['lsp', undefined]);
});
test('idle servers show the configured count', async () => {
  const app = await install(upstream([{ server_id: 'gopls', state: 'configured' }, { server_id: 'typescript', state: 'stopped' }]));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP 2 configured']);
});
test('missing status tool is harmless', async () => {
  const app = await install(() => {});
  await app.emit('session_start');
  assert.deepEqual(app.statuses, []);
});
test('status errors degrade visibly and never reject tool results', async () => {
  const app = await install(pi => pi.registerTool({ name: 'lsp_status', async execute() { throw Error('server unavailable'); } }));
  await app.emit('tool_result');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP status unavailable']);
});
test('disabled status still installs the upstream tools', async () => {
  let installed = false;
  const app = await install(pi => { installed = true; pi.registerTool({ name: 'lsp_status' }); }, { enabled: false });
  await app.emit('session_start');
  assert.equal(installed, true);
  assert.deepEqual(app.statuses, []);
});

test('groups running instances across roots without regrouping distinct servers', async () => {
  const app = await install(upstream([{ server_id: 'basedpyright', root_path: '/one', state: 'running' }, { server_id: 'json', root_path: '/one', state: 'running' }, { server_id: 'basedpyright', root_path: '/two', state: 'running' }, { server_id: 'basedpyright', root_path: '/three', state: 'running' }]));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP basedpyright ● ×3 · json ●']);
});
test('starting instances take precedence over running in either order', async () => {
  const app = await install(upstream([{ server_id: 'ruff', state: 'running' }, { server_id: 'ruff', state: 'starting' }, { server_id: 'pyrefly', state: 'starting' }, { server_id: 'pyrefly', state: 'running' }]));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP ruff ◌ ×2 · pyrefly ◌ ×2']);
});
test('unavailable instances stay visible ahead of starting and running in either order', async () => {
  const app = await install(upstream([{ server_id: 'ruff', state: 'running' }, { server_id: 'ruff', state: 'starting' }, { server_id: 'ruff', state: 'unavailable' }, { server_id: 'pyrefly', state: 'unavailable' }, { server_id: 'pyrefly', state: 'starting' }, { server_id: 'pyrefly', state: 'running' }]));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP ruff ! ×3 · pyrefly ! ×3']);
});
test('counts only active instances in each group', async () => {
  const app = await install(upstream([{ server_id: 'ruff', state: 'running' }, { server_id: 'ruff', state: 'stopped' }, { server_id: 'ruff', state: 'disabled' }, { server_id: 'ruff', state: 'configured' }]));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP ruff ●']);
});
test('shows starting and unavailable singletons without a count', async () => {
  const app = await install(upstream([{ server_id: 'ruff', state: 'starting' }, { server_id: 'pyrefly', state: 'unavailable' }]));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP ruff ◌ · pyrefly !']);
});

test('refresh rebuilds groups as instances stop', async () => {
  const rows = [{ server_id: 'ruff', state: 'running' }, { server_id: 'ruff', state: 'running' }];
  const app = await install(upstream(rows));
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP ruff ● ×2']);
  rows[1].state = 'stopped';
  await app.emit('tool_result');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP ruff ●']);
  rows[0].state = 'stopped';
  await app.emit('agent_end');
  assert.deepEqual(app.statuses.at(-1), ['lsp', 'LSP 2 configured']);
});
