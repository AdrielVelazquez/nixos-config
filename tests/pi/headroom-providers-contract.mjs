import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const f = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const ids = config => Object.keys(config.adapters).sort();
assert.deepEqual(ids(f.configured), ['llm-platform', 'openai-codex', 'pi-providers']);
assert.deepEqual(ids(f.codexOnly), ['openai-codex']);
assert.deepEqual(ids(f.goOnly), ['pi-providers']);
assert.deepEqual(ids(f.llmOnly), ['llm-platform']);
for (const name of ['unconfigured', 'globalOff', 'llmAbsent']) {
  assert.deepEqual(ids(f[name]), [], name);
  assert.deepEqual(f[name].entries, [], name);
  assert.ok(!f[name].required.some(entry => ['headroom-providers', 'headroom-codex'].includes(entry.id)), name);
  assert.ok(f[name].assertions.every(Boolean), name + ': turning routing off must be valid');
}
assert.equal(f.unconfigured.llmPlatform, true, 'turning proxy routing off must not remove the provider');
assert.deepEqual(f.configured.adapters['pi-providers'], {
  urlEnv: 'HEADROOM_PI_PROVIDERS_PROXY_URL',
  requiredEnv: 'HEADROOM_PI_PROVIDERS_PROXY_REQUIRED',
  upstreamOrigins: ['https://opencode.ai'],
});
assert.deepEqual(f.configured.adapters['openai-codex'], {
  urlEnv: 'HEADROOM_PI_CODEX_PROXY_URL',
  requiredEnv: 'HEADROOM_PI_CODEX_PROXY_REQUIRED',
  upstreamOrigins: ['https://chatgpt.com'],
});
for (const name of ['configured', 'codexOnly', 'goOnly', 'framework', 'razer']) {
  const config = f[name];
  for (const [id, suffix] of [['headroom-providers', 'pi-headroom-providers.ts'], ['headroom-codex', 'pi-headroom-codex.ts']]) {
    const entry = config.entries.find(path => path.endsWith(suffix));
    assert.deepEqual(config.required.filter(item => item.id === id), entry ? [{ id, path: entry }] : [], name);
    if (entry) assert.ok(readFileSync(entry, 'utf8').includes(id + '.ts'), name + ': generated entry must resolve its implementation');
  }
}
assert.deepEqual(ids(f.framework), ['llm-platform', 'openai-codex']);
assert.deepEqual(ids(f.razer), ['openai-codex', 'pi-providers']);
assert.equal(f.razer.llmPlatform, false, 'Razer remains independent of LLM Platform');
console.log('PASS: provider switches independently control adapters and child entries, without disabling direct providers');
