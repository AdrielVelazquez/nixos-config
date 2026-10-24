import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const [fixturePath, catalogDir] = process.argv.slice(2);
const f = JSON.parse(readFileSync(fixturePath, 'utf8'));

assert.equal(f.llmPlatform, false, 'Razer must not enable the LLM Platform provider');
assert.equal(f.headroom, true, 'Razer Pi must run through Headroom');
assert.equal(f.routing, true, 'Razer Pi must use native subagent routing');
assert.equal(f.settings.defaultProvider, 'roles');
assert.equal(f.settings.defaultModel, 'auto');
assert.deepEqual(f.providers, {
  'opencode-go': 'https://opencode.ai/inference/go/v1',
  opencode: 'https://opencode.ai/inference/v1',
});
assert.ok(f.settings.extensions.some(path => path.endsWith('pi-headroom-providers.ts')), 'provider routing entry is not loaded');
assert.ok(f.required.includes('headroom') && f.required.includes('headroom-providers'), `required child extensions: ${f.required}`);

const expectedRoles = {
  default: 'opencode-go/kimi-k2.7-code:off', plan: 'opencode-go/glm-5.3:high', slow: 'opencode-go/glm-5.3:max',
  smol: 'opencode-go/glm-5.3-flash:low', commit: '@smol', widget: '@smol',
  tiny: 'opencode/deepseek-v4.1-flash-free:low', memory: '@tiny',
  task: 'opencode-go/kimi-k2.7-code:off', advisor: 'opencode-go/glm-5.3:high', vision: 'opencode-go/kimi-k2.7-code:off',
};
const expectedAgents = {
  build: 'opencode-go/kimi-k2.7-code:off', plan: '@plan', scout: 'opencode-go/glm-5.3-flash:low',
  explore: 'opencode/deepseek-v4.1-flash-free:low', title: '@tiny',
};
assert.deepEqual(f.roles, expectedRoles);
assert.deepEqual(f.taskAgents, expectedAgents);

const catalogs = new Map();
function catalog(provider) {
  if (!catalogs.has(provider)) {
    const data = JSON.parse(readFileSync(join(catalogDir, `${provider}.json`), 'utf8'));
    const models = {};
    for (const group of Object.values(data)) for (const [key, model] of Object.entries(group)) if (key.startsWith('chat:')) models[key.slice(5)] = model;
    catalogs.set(provider, models);
  }
  return catalogs.get(provider);
}
function resolve(selector, seen = []) {
  const [reference, level] = selector.split(',')[0].trim().split(':');
  if (reference.startsWith('@')) {
    const role = reference.slice(1);
    assert.ok(!seen.includes(role), `alias cycle through ${role}`);
    assert.ok(f.roles[role], `alias @${role} names an unset role`);
    const target = resolve(f.roles[role], [...seen, role]);
    return level ? { ...target, thinking: level } : target;
  }
  const slash = reference.indexOf('/');
  return { provider: reference.slice(0, slash), id: reference.slice(slash + 1), thinking: level };
}
function verify(label, selector) {
  const { provider, id, thinking } = resolve(selector);
  assert.ok(f.providers[provider], `${label}: provider ${provider} is not routed through Headroom`);
  const model = catalog(provider)[id];
  assert.ok(model, `${label}: ${provider}/${id} is not in Pi's catalog`);
  assert.equal(model.baseUrl, f.providers[provider], `${label}: catalog base URL differs from the declared upstream`);
  const map = model.thinkingLevelMap;
  assert.ok(thinking, `${label}: ${selector} needs an explicit thinking level`);
  assert.ok(!map || map[thinking] !== null, `${label}: ${provider}/${id} does not accept thinking level ${thinking}`);
  return model;
}
for (const [role, selector] of Object.entries(f.roles)) verify(`role ${role}`, selector);
for (const [agent, selector] of Object.entries(f.taskAgents)) verify(`agent ${agent}`, selector);
assert.ok(verify('vision', f.roles.vision).input.includes('image'), 'the vision role needs an image-capable model');

assert.match(f.agents.build, /model: opencode-go\/kimi-k2\.7-code\nthinking: off/);
assert.match(f.agents.plan, /model: opencode-go\/glm-5\.3\nthinking: high/);
assert.match(f.agents.scout, /model: opencode-go\/glm-5\.3-flash\nthinking: low/);
assert.match(f.agents.explore, /model: opencode\/deepseek-v4\.1-flash-free\nthinking: low/);
assert.match(f.agents.title, /model: opencode\/deepseek-v4\.1-flash-free\nthinking: low/);

const everything = JSON.stringify({ settings: f.settings, agents: f.agents, mcp: readFileSync(f.mcpFile, 'utf8') });
for (const needle of ['llm-platform', 'llmplatform', 'snooguts']) assert.ok(!everything.includes(needle), `Razer's Pi configuration mentions ${needle}`);
console.log('PASS: Razer Pi roles resolve in the catalog at supported thinking levels, are routed through Headroom, and carry no LLM Platform configuration');
