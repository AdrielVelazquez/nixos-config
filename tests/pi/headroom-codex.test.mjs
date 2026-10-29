import assert from 'node:assert/strict';
import { test } from 'node:test';

const module = await import('../../dotfiles/pi/extensions/headroom-codex.ts').catch(() => ({}));
const proxy = 'http://127.0.0.1:19879';
const routing = { urlEnv: 'HEADROOM_PI_CODEX_PROXY_URL', requiredEnv: 'HEADROOM_PI_CODEX_PROXY_REQUIRED' };
const contract = { HEADROOM_PROXY_URL: proxy, HEADROOM_PI_CODEX_PROXY_URL: proxy, HEADROOM_PI_CODEX_PROXY_REQUIRED: '1' };
function run(env) {
  assert.equal(typeof module.routeCodexThroughHeadroom, 'function', 'Codex routing adapter is available');
  const registered = [], handlers = new Map();
  module.routeCodexThroughHeadroom({
    registerProvider: (id, config) => registered.push([id, config]),
    on: (event, handler) => handlers.set(event, handler),
  }, routing, env);
  return { registered, handlers };
}

test('redirects only Codex while retaining native authentication, catalog and streaming implementations', () => {
  const { registered } = run(contract);
  assert.deepEqual(registered, [['openai-codex', {
    baseUrl: proxy + '/v1',
    headers: { 'x-headroom-base-url': 'https://chatgpt.com', 'x-client': 'codex' },
  }]]);
});
for (const [name, env] of [
  ['missing launcher', {}],
  ['foreign URL', { ...contract, HEADROOM_PI_CODEX_PROXY_URL: 'http://127.0.0.1:19880' }],
  ['not required', { ...contract, HEADROOM_PI_CODEX_PROXY_REQUIRED: '0' }],
  ['non-loopback', { ...contract, HEADROOM_PROXY_URL: 'http://10.0.0.5:8787', HEADROOM_PI_CODEX_PROXY_URL: 'http://10.0.0.5:8787' }],
]) test('refuses direct Codex inference: ' + name, () => {
  const { registered, handlers } = run(env);
  assert.deepEqual(registered, [['openai-codex', { baseUrl: 'http://127.0.0.1:1/headroom-required' }]]);
  const notices = [];
  handlers.get('session_start')({}, { ui: { notify: (message, level) => notices.push({ message, level }) } });
  assert.equal(notices.length, 1);
  assert.equal(notices[0].level, 'error');
});
