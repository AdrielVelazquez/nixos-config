import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, writeFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { createServer } from 'node:http';
import { installWork } from '../../dotfiles/omp/work.ts';
import { saveProjectSelection } from '../../dotfiles/omp/reddit-state.mjs';

test('main bootstrap preserves native prompt blocks and never enters children', async () => {
  const root = await mkdtemp(join(tmpdir(), 'omp-extension-'));
  const gateway = createServer((_req, res) => res.end('{"data":[{"id":"gpt-6.1-sol"}]}'));
  await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
  try {
    const helper = join(root, 'transport.py');
    await writeFile(helper, 'import json\nprint(json.dumps({"proxyURL":"http://127.0.0.1:19999","project":"/fixture","memoryDB":"/fixture/memory.db"}))\n');
    const hooks = new Map(), registrations = [];
    const pi = { on: (name, fn) => hooks.set(name, fn), registerProvider: (_name, config) => registrations.push(config), registerCommand() {} };
    await installWork(pi, { python: 'python3', helper, manifest: join(root, 'manifest'),
      gatewayOrigin: `http://127.0.0.1:${gateway.address().port}`, allowTestLoopback: true,
      projectId: 'fixture-user', bootstrap: 'BOOTSTRAP', routes: {} });
    assert.equal(registrations[0].models.length, 1, 'cold default resolution needs a complete initial catalog');
    const blocks = ['Native block A', 'Native block B'];
    assert.deepEqual(hooks.get('before_agent_start')({ systemPrompt: blocks }, { agent: { kind: 'main' } }),
      { systemPrompt: ['Native block A', 'Native block B', 'BOOTSTRAP'] });
    assert.deepEqual(blocks, ['Native block A', 'Native block B']);
    assert.equal(hooks.get('before_agent_start')({ systemPrompt: blocks }, { agent: { kind: 'sub', name: 'scout' } }), undefined);
  } finally { gateway.closeAllConnections(); await new Promise(resolve => gateway.close(resolve)); await rm(root, { recursive: true, force: true }); }
});

test('provider initialization failure does not discard worker gates with the native factory', async () => {
  const hooks = new Map(), notifications = [];
  const pi = { on: (name, fn) => hooks.set(name, fn), registerProvider() { assert.fail('invalid auth must not register a usable provider'); }, registerCommand() {} };
  await installWork(pi, { gatewayOrigin: 'https://gateway.invalid', projectId: 'INVALID/PROJECT', manifest: 'bad-project', routes: {} });
  assert.equal(hooks.get('tool_call')({ toolName: 'write', input: {} }, { agent: { kind: 'sub', name: 'scout' } }).block, true);
  assert.equal((await hooks.get('before_subagent_spawn')({ agent: 'scout' }, {})).block, true);
  await hooks.get('session_start')({}, { ui: { notify: (...args) => notifications.push(args) } });
  assert.match(notifications[0][0], /LLM Platform.*unavailable.*Invalid LLM Platform project override/);
});

test('factory applies the saved default project once and children keep the live project despite preference edits', async () => {
  const root = await mkdtemp(join(tmpdir(), 'omp-project-factory-'));
  const gateway = createServer((_req, res) => res.end('{"data":[{"id":"gpt-6.1-sol"}]}'));
  await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
  try {
    const helper = join(root, 'transport.py'), agentDir = join(root, 'agent');
    await mkdir(agentDir);
    await writeFile(helper, 'import json\nprint(json.dumps({"proxyURL":"http://127.0.0.1:19999","project":"/fixture","memoryDB":"/fixture/memory.db"}))\n');
    await saveProjectSelection(agentDir, process.cwd(), 'alpha-project');
    const registrations = [];
    const pi = { on() {}, registerCommand() {}, registerProvider: (_name, config) => registrations.push(config) };
    const options = { python: 'python3', helper, manifest: join(root, 'manifest'),
      gatewayOrigin: `http://127.0.0.1:${gateway.address().port}`, allowTestLoopback: true,
      projectId: 'opencode-dev', projectSelection: { id: 'opencode-dev', source: 'default', locked: false },
      reddit: { agentDir }, routes: {} };
    await installWork(pi, options);
    assert.equal(registrations.at(-1).apiKey, 'project/alpha-project');
    await writeFile(join(agentDir, 'reddit/projects.json'), '{bad-json');
    await installWork(pi, options);
    assert.equal(registrations.length, 2, 'child must still rebind the existing provider snapshot');
    assert.equal(registrations.at(-1).apiKey, 'project/alpha-project');
  } finally { gateway.closeAllConnections(); await new Promise(resolve => gateway.close(resolve)); await rm(root, { recursive: true, force: true }); }
});
