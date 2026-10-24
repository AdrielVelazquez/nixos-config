import assert from 'node:assert/strict';
import { test } from 'node:test';
import { UNAVAILABLE_BASE_URL, routeProvidersThroughHeadroom } from '../../dotfiles/pi/extensions/headroom-providers.ts';

const routing = {
  routes: { 'opencode-go': 'https://opencode.ai/inference/go/v1', opencode: 'https://opencode.ai/inference/v1' },
  urlEnv: 'HEADROOM_PI_PROVIDERS_PROXY_URL',
  requiredEnv: 'HEADROOM_PI_PROVIDERS_PROXY_REQUIRED',
};
const proxy = 'http://127.0.0.1:19879';
const contract = { HEADROOM_PROXY_URL: proxy, HEADROOM_PI_PROVIDERS_PROXY_URL: proxy, HEADROOM_PI_PROVIDERS_PROXY_REQUIRED: '1' };

function run(env) {
  const registered = [], handlers = new Map();
  routeProvidersThroughHeadroom({
    registerProvider: (id, config) => registered.push([id, config]),
    on: (event, handler) => handlers.set(event, handler),
  }, routing, env);
  return { registered, handlers };
}
function refused({ registered, handlers }) {
  assert.deepEqual(registered, Object.keys(routing.routes).map(id => [id, { baseUrl: UNAVAILABLE_BASE_URL }]));
  const notices = [];
  handlers.get('session_start')({}, { ui: { notify: (message, level) => notices.push({ message, level }) } });
  assert.equal(notices.length, 1);
  assert.equal(notices[0].level, 'error');
  assert.match(notices[0].message, /managed Headroom launcher/);
}

test('routes every declared provider through the owned proxy; the header is the upstream base without /v1, which the proxy re-appends', () => {
  const { registered } = run(contract);
  assert.deepEqual(registered, [
    ['opencode-go', { baseUrl: `${proxy}/v1`, headers: { 'x-headroom-base-url': 'https://opencode.ai/inference/go' } }],
    ['opencode', { baseUrl: `${proxy}/v1`, headers: { 'x-headroom-base-url': 'https://opencode.ai/inference' } }],
  ]);
});

test('refuses direct inference when the launcher contract is absent', () => refused(run({})));

test('refuses a contract whose URL differs from HEADROOM_PROXY_URL', () =>
  refused(run({ ...contract, HEADROOM_PI_PROVIDERS_PROXY_URL: 'http://127.0.0.1:19880' })));

test('refuses a non-loopback proxy URL', () => {
  const remote = 'http://10.0.0.5:8787';
  refused(run({ ...contract, HEADROOM_PROXY_URL: remote, HEADROOM_PI_PROVIDERS_PROXY_URL: remote }));
});

test('refuses a contract that is not marked required', () =>
  refused(run({ ...contract, HEADROOM_PI_PROVIDERS_PROXY_REQUIRED: '0' })));

test('an Anthropic-protocol model is based on the bare proxy, since its client appends /v1/messages itself; the others keep /v1', () => {
  const { registered, handlers } = run(contract);
  const headers = { 'x-headroom-base-url': 'https://opencode.ai/inference/go' };
  const model = (id, api) => ({ id, provider: 'opencode-go', api, baseUrl: `${proxy}/v1`, type: 'chat' });
  const chat = [model('glm-5.3', 'openai-completions'), model('minimax-m3', 'anthropic-messages'), model('gpt-6-luna', 'openai-responses'),
    model('gemini-4-argon-contributor', 'google-generative-ai')];
  const asked = [];
  handlers.get('session_start')({}, { modelRegistry: { getModelsOfType: (type, provider) => { asked.push([type, provider]); return provider === 'opencode-go' ? chat : []; } } });
  assert.deepEqual(asked.map(([type]) => type), ['chat', 'chat'], 'every declared provider is looked up once');
  assert.equal(registered.length, 3, 'only the provider that has an Anthropic-protocol model is registered again');
  assert.deepEqual(registered.at(-1), ['opencode-go', { baseUrl: `${proxy}/v1`, headers, models: [
    model('glm-5.3', 'openai-completions'),
    { ...model('minimax-m3', 'anthropic-messages'), baseUrl: proxy },
    model('gpt-6-luna', 'openai-responses'),
    model('gemini-4-argon-contributor', 'google-generative-ai'),
  ] }]);
});

test('a provider without Anthropic-protocol models is left as first registered', () => {
  const { registered, handlers } = run(contract);
  handlers.get('session_start')({}, { modelRegistry: { getModelsOfType: () => [{ id: 'glm-5.3', provider: 'opencode-go', api: 'openai-completions', baseUrl: `${proxy}/v1`, type: 'chat' }] } });
  assert.equal(registered.length, 2);
});
