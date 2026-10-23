import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createProviderService } from '../../dotfiles/omp/provider-core.mjs';

const rpc = '/api/reddit.llmplatform.controlplane.project.v1alpha.ProjectService/GetOrCreateUserProject';
const transport = { proxyURL: 'http://127.0.0.1:12345', project: '/synthetic/worktree' };
const row = (id = 'fixture/model') => ({ id, x_llm_platform: { capabilities: {
  api: ['chat_completions', 'responses'], tools: true, reasoning: true,
  reasoning_efforts: ['none', 'low', 'high'], modalities: { input: ['text', 'image'] },
}, limits: { context_window_tokens: 9000, max_input_tokens: 8000, max_output_tokens: 111 },
pricing: { input: 4, output: 8, cache_read_input: 1, cache_write_5m_input: 3 } } });

function fixture(env = {}) {
  const calls = [], state = { rows: [row()], status: 200 };
  const service = createProviderService({ gatewayOrigin: 'https://gateway.invalid', env, timeoutMs: 50, retries: 0 }, {
    acquire: async () => transport,
    fetch: async (url, options) => {
      calls.push({ url, options });
      return new Response(JSON.stringify(url.endsWith(rpc) ? { id: 'fixture-user' } : { data: state.rows }), { status: state.status });
    },
  });
  return { service, calls, state };
}

test('runtime project resolution is single-flight, discovery direct and every model routed to owned proxy', async () => {
  const f = fixture();
  const [a, b] = await Promise.all([f.service.providerConfig(), f.service.providerConfig()]);
  assert.equal(a.apiKey, 'project/fixture-user'); assert.equal(a, b);
  assert.equal(f.calls.filter(c => c.url.endsWith(rpc)).length, 1);
  const [model] = await a.fetchDynamicModels();
  assert.equal(model.id, 'fixture/model'); assert.equal(model.api, 'openai-responses');
  assert.equal(model.contextWindow, 8000); assert.equal(model.maxTokens, 111);
  assert.deepEqual(model.cost, { input: 4, output: 8, cacheRead: 1, cacheWrite: 3 });
  assert.deepEqual(model.thinking.efforts, ['low', 'high']);
  assert.deepEqual(model.input, ['text', 'image']);
  assert.equal(model.headers['x-headroom-base-url'], 'https://gateway.invalid');
  assert.equal(model.headers['x-headroom-original-path'], '/v1/openai/responses');
  assert.equal(model.headers['x-headroom-cwd'], '/synthetic/worktree');
  assert.equal(a.baseUrl, transport.proxyURL + '/v1');
  assert.equal(f.calls.at(-1).options.headers.Authorization, 'Bearer project/fixture-user');
  assert.ok(f.calls.every(c => c.url.startsWith('https://gateway.invalid/')));
  f.state.rows = [row('replacement')];
  assert.deepEqual((await a.fetchDynamicModels()).map(m => m.id), ['replacement']);
});

test('explicit validated project wins; invalid values fail without provisioning', async () => {
  const f = fixture({ LLM_PLATFORM_PROJECT_ID: 'explicit-project' });
  assert.equal((await f.service.providerConfig()).apiKey, 'project/explicit-project');
  assert.equal(f.calls.length, 0);
  const bad = fixture({ LLM_PLATFORM_PROJECT_ID: '../bad' });
  await assert.rejects(bad.service.providerConfig(), /invalid.*project/i);
  assert.equal(bad.calls.length, 0);
});

test('the resolved OpenCode project selection is preserved without provisioning another project', async () => {
  let fetches = 0;
  const service = createProviderService({ gatewayOrigin: 'https://gateway.invalid', projectId: 'configured-oc-project', env: { LLM_PLATFORM_PROJECT_ID: 'other-env-project' } }, {
    acquire: async () => transport,
    fetch: async () => { fetches++; return new Response('{"id":"unexpected-project"}'); },
  });
  assert.equal((await service.providerConfig()).apiKey, 'project/configured-oc-project');
  assert.equal(fetches, 0);
});

test('explicit unsupported capabilities never become guessed support; auth denial is not stale fallback', async () => {
  const f = fixture(); const config = await f.service.providerConfig();
  f.state.rows = [row(), { id: 'gpt-6.1-sol', x_llm_platform: { capabilities: { api: [], tools: true } } },
    { ...row('tool-less'), x_llm_platform: { capabilities: { api: ['responses'], tools: false } } }];
  assert.deepEqual((await config.fetchDynamicModels()).map(m => m.id), ['fixture/model']);
  f.state.status = 403;
  await assert.rejects(config.fetchDynamicModels(), /403/);
});

test('owned transport failure never falls back to an upstream endpoint', async () => {
  let fetches = 0;
  const service = createProviderService({ gatewayOrigin: 'https://gateway.invalid', env: {} }, {
    acquire: async () => { throw new Error('owned proxy unavailable'); }, fetch: async () => { fetches++; },
  });
  await assert.rejects(service.providerConfig(), /owned proxy unavailable/);
  assert.equal(fetches, 0);
});

test('a missing configured role model fails instead of enabling native title/parent fallback', async () => {
  const service = createProviderService({ gatewayOrigin: 'https://gateway.invalid', env: { LLM_PLATFORM_PROJECT_ID: 'fixture-user' }, requiredModels: ['must-exist'] }, {
    acquire: async () => transport,
    fetch: async () => new Response(JSON.stringify({ data: [row()] })),
  });
  const config = await service.providerConfig();
  await assert.rejects(config.fetchDynamicModels(), /configured.*model.*unavailable/i);
});

test('child registration carries the last complete catalog including owned routing headers', async () => {
  const f = fixture({ LLM_PLATFORM_PROJECT_ID: 'fixture-user' });
  const first = await f.service.providerConfig();
  await first.fetchDynamicModels();
  const before = f.calls.length;
  const child = await f.service.providerConfig();
  assert.equal(child.models.length, 1, 'child factory must not empty the shared registry');
  assert.equal(child.models[0].id, 'fixture/model');
  assert.equal(child.models[0].headers['x-headroom-base-url'], 'https://gateway.invalid');
  assert.equal(child.baseUrl, 'http://127.0.0.1:12345/v1');
  assert.equal(f.calls.length, before, 'registration itself must not rediscover');
});
