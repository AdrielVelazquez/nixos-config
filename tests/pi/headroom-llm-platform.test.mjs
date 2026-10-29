import assert from 'node:assert/strict';
import { test } from 'node:test';

const module = await import('../../dotfiles/pi/extensions/headroom-llm-platform.ts').catch(() => ({}));
const proxy = 'http://127.0.0.1:19879';
const contract = { HEADROOM_PROXY_URL: proxy, LLM_PLATFORM_INFERENCE_PROXY_URL: proxy, LLM_PLATFORM_INFERENCE_PROXY_REQUIRED: '1' };
function initialize(required, callback, env) {
  assert.equal(typeof module.withLlmPlatformProxy, 'function', 'managed LLM Platform initialization exists');
  return module.withLlmPlatformProxy(required, callback, env);
}
for (const [name, env] of [
  ['missing contract', { HEADROOM_PROXY_URL: proxy }],
  ['foreign proxy', { ...contract, LLM_PLATFORM_INFERENCE_PROXY_URL: 'http://127.0.0.1:19880' }],
  ['non-loopback proxy', { HEADROOM_PROXY_URL: 'http://10.0.0.5:8787', LLM_PLATFORM_INFERENCE_PROXY_URL: 'http://10.0.0.5:8787', LLM_PLATFORM_INFERENCE_PROXY_REQUIRED: '1' }],
  ['not required', { ...contract, LLM_PLATFORM_INFERENCE_PROXY_REQUIRED: '0' }],
]) test('enabled LLM routing refuses initialization: ' + name, () => {
  let called = false;
  assert.throws(() => initialize(true, () => { called = true; }, env), /managed Headroom launcher/);
  assert.equal(called, false, 'no direct or foreign provider may be registered');
});
test('enabled routing preserves the exact owned contract during registration', () => {
  const env = { ...contract };
  const captured = initialize(true, () => ({ ...env }), env);
  assert.deepEqual(captured, contract);
  assert.deepEqual(env, contract);
});
test('disabled routing removes inherited contract while provider snapshots it, then restores the ambient environment', async () => {
  const env = { ...contract, UNRELATED: 'retained' };
  const before = { ...env };
  const pending = initialize(false, () => Promise.resolve({ ...env }), env);
  assert.deepEqual(env, before, 'do not hold process-global mutations across an await');
  assert.deepEqual(await pending, { HEADROOM_PROXY_URL: proxy, UNRELATED: 'retained' });
});
test('disabled routing restores the environment after synchronous provider initialization failure', () => {
  const env = { ...contract };
  assert.throws(() => initialize(false, () => { throw new Error('fixture failure'); }, env), /fixture failure/);
  assert.deepEqual(env, contract);
});
