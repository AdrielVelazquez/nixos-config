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
