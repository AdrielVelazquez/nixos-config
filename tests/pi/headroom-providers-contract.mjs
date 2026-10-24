import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const f = JSON.parse(readFileSync(process.argv[2], 'utf8'));
const configured = f.configured, unconfigured = f.unconfigured;

assert.deepEqual(configured.adapters['pi-providers'], {
  urlEnv: 'HEADROOM_PI_PROVIDERS_PROXY_URL',
  requiredEnv: 'HEADROOM_PI_PROVIDERS_PROXY_REQUIRED',
  upstreamOrigins: ['https://opencode.ai'],
});
assert.ok(configured.adapters['llm-platform'], 'the LLM Platform adapter is independent of provider routing');
assert.ok(configured.entry, 'a routing entry must be installed');
assert.deepEqual(configured.required.filter(entry => entry.id === 'headroom-providers'), [{ id: 'headroom-providers', path: configured.entry }]);
const text = readFileSync(configured.entry, 'utf8');
assert.match(text, /headroom-providers\.ts/);
assert.ok(text.includes('"opencode-go":"https://opencode.ai/inference/go/v1"'), text);
assert.ok(text.includes('"urlEnv":"HEADROOM_PI_PROVIDERS_PROXY_URL"') && text.includes('"requiredEnv":"HEADROOM_PI_PROVIDERS_PROXY_REQUIRED"'), text);

assert.equal(unconfigured.adapters['pi-providers'], undefined);
assert.equal(unconfigured.entry, null);
assert.deepEqual(unconfigured.required.filter(entry => entry.id === 'headroom-providers'), []);
console.log('PASS: provider routing adds its adapter, entry and required child extension only when providers are declared');
