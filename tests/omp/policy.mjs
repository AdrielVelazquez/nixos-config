import assert from 'node:assert/strict';
import { test } from 'node:test';
import { toolDecision, spawnDecision } from '../../dotfiles/omp/policy.mjs';
const child = name => ({ agent: { kind: 'sub', name } });

test('read-only children cannot use shell, writes, eval, delegation or MCP mutations regardless of hints', () => {
  for (const name of ['scout', 'explore']) for (const tool of ['bash', 'exec', 'eval', 'task', 'write', 'edit', 'mcp__github_create_issue', 'mcp__headroom_memory_memory_save', 'unknown']) {
    assert.equal(toolDecision({ toolName: tool, input: { path: 'xd://mcp/github' }, annotations: { readOnlyHint: true } }, child(name)).block, true, name + ':' + tool);
  }
  assert.equal(toolDecision({ toolName: 'write', input: {} }, { agent: { kind: 'main' } }), undefined);
});
test('local explore has no web and read cannot invoke internal executable or model-query routes', () => {
  assert.equal(toolDecision({ toolName: 'read', input: { path: 'src/file.ts' } }, child('explore')), undefined);
  for (const path of ['https://example.invalid', 'agent://run', 'image.png?q=describe', 'image.png?%71=describe', 'xd://tool/run']) {
    assert.equal(toolDecision({ toolName: 'read', input: { path } }, child('explore'))?.block, true, path);
  }
  assert.equal(toolDecision({ toolName: 'web_search', input: {} }, child('explore')).block, true);
  assert.equal(toolDecision({ toolName: 'read', input: { path: 'https://example.invalid' } }, child('scout')), undefined);
  assert.equal(toolDecision({ toolName: 'mcp__headroom_stats', input: {} }, child('scout')), undefined);
});
test('all native search path forms stay local and read cannot fan out into unvalidated routes', () => {
  const routes = ['https://example.invalid', 'www.example.invalid/x', 'https:/example.invalid',
    'src/a.ts;https://example.invalid', 'src/a.ts;xd://tool', 'custom:item', 'urn:example:doc',
    'local:/x', '/abs/local://x', 'a#b.png?q=describe', 'a#b.png?%71=describe'];
  for (const name of ['scout', 'explore']) {
    for (const tool of ['find', 'grep', 'glob']) {
      for (const path of routes) assert.equal(toolDecision({ toolName: tool, input: { path } }, child(name))?.block, true, `${name}:${tool}:${path}`);
      assert.equal(toolDecision({ toolName: tool, input: { path: ['src', './README.md'] } }, child(name)), undefined);
      assert.equal(toolDecision({ toolName: tool, input: { path: ['src', 'custom:item'] } }, child(name))?.block, true);
      assert.equal(toolDecision({ toolName: tool, input: { pattern: 'TODO' } }, child(name)), undefined);
    }
    for (const path of routes.slice(3)) assert.equal(toolDecision({ toolName: 'read', input: { path } }, child(name))?.block, true, `${name}:read:${path}`);
  }
  for (const path of routes.slice(0, 3)) assert.equal(toolDecision({ toolName: 'read', input: { path } }, child('explore'))?.block, true, path);
  assert.equal(toolDecision({ toolName: 'read', input: { path: 'skill://systematic-debugging' } }, child('explore')), undefined);
  assert.equal(toolDecision({ toolName: 'read', input: { path: './src/file.ts:1-20' } }, child('explore')), undefined);
});
test('native task/eval preflight pins only an available authenticated configured worker, never a parent fallback', async () => {
  const route = 'llmplatform/gpt-6.1-sol:low';
  const ctx = { modelRegistry: { find: () => ({ provider: 'llmplatform', id: 'gpt-6.1-sol' }), getApiKey: async () => 'project/fixture-user' } };
  assert.equal((await spawnDecision({ scout: route }, { agent: 'scout', patterns: [route] }, ctx)).model, route);
  assert.equal((await spawnDecision({ scout: route }, { agent: 'unknown', patterns: [] }, ctx)).block, true);
  assert.equal((await spawnDecision({ scout: route }, { agent: 'scout', patterns: ['other/model'] }, ctx)).block, true);
  ctx.modelRegistry.getApiKey = async () => undefined;
  assert.equal((await spawnDecision({ scout: route }, { agent: 'scout', patterns: [route] }, ctx)).block, true);
});
