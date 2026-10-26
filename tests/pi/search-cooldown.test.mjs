import assert from 'node:assert/strict';
import test from 'node:test';
import { createExaKeyScope, createProviderCooldown, withProviderCooldown } from '../../dotfiles/pi/extensions/search-cooldown-core.ts';

const respond = (status, headers = {}) => new Response(`status ${status}`, { status, headers });
const clock = () => { const state = { now: 1_000_000 }; return { state, now: () => state.now }; };
const setup = (script, hosts = ['api.exa.ai', 'search.parallel.ai']) => {
  const calls = [], time = clock();
  const inner = async (input) => { const url = String(input); calls.push(url); return script(url, calls.length); };
  return { calls, time, fetch: withProviderCooldown(inner, { hosts, now: time.now }) };
};

test('a 429 from a provider is returned and the provider is skipped until it cools down', async () => {
  const { fetch, calls, time } = setup(() => respond(429));
  assert.equal((await fetch('https://api.exa.ai/search')).status, 429);
  const skipped = await fetch('https://api.exa.ai/search');
  assert.equal(skipped.status, 429);
  assert.match(await skipped.text(), /api\.exa\.ai.*cooling down.*429/);
  assert.equal(calls.length, 1, 'the second request never reached the network');
  time.state.now += 61_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2, 'the provider is tried again after the cooldown');
});

test('Retry-After sets the cooldown, within sane bounds', async () => {
  const { fetch, calls, time } = setup((_url, n) => respond(429, { 'retry-after': n === 1 ? '120' : '1' }));
  await fetch('https://api.exa.ai/search');
  time.state.now += 119_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 1, 'still cooling at 119 s of a 120 s Retry-After');
  time.state.now += 2_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2);
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2, 'a Retry-After of 1 s is raised to the 5 s floor');
  time.state.now += 4_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2);
  time.state.now += 2_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 3);
});

test('an absurd Retry-After is capped at five minutes', async () => {
  const { fetch, calls, time } = setup(() => respond(429, { 'retry-after': '86400' }));
  await fetch('https://api.exa.ai/search');
  time.state.now += 301_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2);
});

test('exhausted credits (402) keep the provider out for ten minutes and read as a rate limit to the caller', async () => {
  const { fetch, calls, time } = setup(() => respond(402));
  assert.equal((await fetch('https://api.exa.ai/search')).status, 402, 'the first answer is the real one');
  const skipped = await fetch('https://api.exa.ai/search');
  assert.equal(skipped.status, 429, 'later skips use the status the failover treats as quota');
  assert.match(await skipped.text(), /402/);
  time.state.now += 599_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 1);
  time.state.now += 2_000;
  await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2);
});

test('one provider cooling down does not affect another, and other hosts are untouched', async () => {
  const { fetch, calls } = setup((url) => respond(url.includes('api.exa.ai') ? 429 : 200));
  await fetch('https://api.exa.ai/search');
  assert.equal((await fetch('https://search.parallel.ai/mcp')).status, 200);
  assert.equal((await fetch('https://example.com/a')).status, 200);
  await fetch('https://example.com/a');
  assert.equal(calls.filter((url) => url.includes('example.com')).length, 2);
});

test('errors other than throttling never start a cooldown', async () => {
  const { fetch, calls } = setup(() => respond(500));
  await fetch('https://api.exa.ai/search'); await fetch('https://api.exa.ai/search');
  assert.equal(calls.length, 2);
  const failing = setup(() => { throw new TypeError('fetch failed'); });
  await assert.rejects(failing.fetch('https://api.exa.ai/search'), /fetch failed/);
  await assert.rejects(failing.fetch('https://api.exa.ai/search'), /fetch failed/);
  assert.equal(failing.calls.length, 2);
});

test('URL and Request inputs are matched by host', async () => {
  const { fetch, calls } = setup(() => respond(429));
  await fetch(new URL('https://api.exa.ai/search'));
  await fetch(new Request('https://api.exa.ai/search', { method: 'POST', body: '{}' }));
  assert.equal(calls.length, 1);
});

test('a provider reports whether it is cooling down', async () => {
  const time = clock();
  const cooldown = createProviderCooldown({ hosts: ['api.exa.ai'], now: time.now });
  const fetch = cooldown.wrap(async () => respond(402));
  assert.equal(cooldown.isCooling('api.exa.ai'), false);
  await fetch('https://api.exa.ai/search');
  assert.equal(cooldown.isCooling('api.exa.ai'), true);
  assert.equal(cooldown.isCooling('search.parallel.ai'), false);
  time.state.now += 601_000;
  assert.equal(cooldown.isCooling('api.exa.ai'), false);
});

const scope = (options = {}) => {
  const env = { ...options.env }, state = { cooling: false, key: 'sops-key', ...options.state };
  const run = createExaKeyScope({ env, readKey: () => { if (state.key instanceof Error) throw state.key; return state.key; }, isCooling: () => state.cooling });
  return { env, state, run };
};

test('the Exa key is in the environment only while a search runs', async () => {
  const { env, run } = scope();
  assert.equal(await run(async () => env.EXA_API_KEY), 'sops-key');
  assert.equal('EXA_API_KEY' in env, false);
});

test('while the keyed API is cooling down the search runs without a key, so Exa answers through its keyless MCP', async () => {
  const { env, state, run } = scope({ env: { EXA_API_KEY: 'ambient' }, state: { cooling: true } });
  assert.equal(await run(async () => env.EXA_API_KEY), undefined);
  assert.equal(env.EXA_API_KEY, 'ambient', 'the surrounding environment is put back');
  state.cooling = false;
  assert.equal(await run(async () => env.EXA_API_KEY), 'sops-key');
});

test('a missing or unreadable key file means the keyless MCP, not an error', async () => {
  for (const key of [null, '', new Error('ENOENT')]) {
    const { env, run } = scope({ state: { key } });
    assert.equal(await run(async () => env.EXA_API_KEY), undefined, String(key));
  }
});

test('the key is removed again when the search fails', async () => {
  const { env, run } = scope();
  await assert.rejects(run(async () => { throw new Error('boom'); }), /boom/);
  assert.equal('EXA_API_KEY' in env, false);
});

test('overlapping searches restore the environment only after the last one ends', async () => {
  const { env, run } = scope({ env: { EXA_API_KEY: 'ambient' } });
  let release;
  const slow = run(() => new Promise((resolve) => { release = resolve; }));
  await run(async () => {});
  assert.equal(env.EXA_API_KEY, 'sops-key', 'the earlier search still has its key');
  release();
  await slow;
  assert.equal(env.EXA_API_KEY, 'ambient');
});

test('a provider that refuses the request (401, 403) is skipped for ten minutes and reads as quota to the caller', async () => {
  for (const status of [401, 403]) {
    const { fetch, calls, time } = setup(() => new Response('secret-looking provider body', { status }));
    const first = await fetch('https://api.exa.ai/search');
    assert.equal(first.status, 429, `${status} is answered as a status the failover moves past`);
    const text = await first.text();
    assert.match(text, new RegExp(`api\\.exa\\.ai.*refused.*${status}`));
    assert.doesNotMatch(text, /secret-looking/, 'the provider body is not repeated, it may echo a credential');
    await fetch('https://api.exa.ai/search');
    assert.equal(calls.length, 1, 'later requests never reach the provider');
    time.state.now += 601_000;
    await fetch('https://api.exa.ai/search');
    assert.equal(calls.length, 2);
  }
});

test('a refusing provider counts as cooling down, so the Exa key is left out and the keyless MCP is used', async () => {
  const time = clock();
  const cooldown = createProviderCooldown({ hosts: ['api.exa.ai'], now: time.now });
  await cooldown.wrap(async () => respond(401))('https://api.exa.ai/search');
  assert.equal(cooldown.isCooling('api.exa.ai'), true);
});
