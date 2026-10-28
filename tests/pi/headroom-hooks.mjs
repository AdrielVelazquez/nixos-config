import assert from 'node:assert/strict';
import { mkdtemp, mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import headroom from '../../dotfiles/pi/extensions/headroom.ts';

test('native header-only events attribute only managed proxied requests, never direct inference', async () => {
  const root = await mkdtemp(join(tmpdir(), 'pi-headroom-hooks-'));
  const before = { ...process.env };
  const started = (await readFile(`/proc/${process.pid}/stat`, 'utf8')).split(')').slice(1).join(')').trim().split(/\s+/)[19];
  const handlers = new Map();
  try {
    await mkdir(join(root, 'leases'));
    await writeFile(join(root, 'state.json'), JSON.stringify({ ready: true, instance: 'fixture', managerPid: process.pid, managerStarted: started, port: 19878, project: root }));
    await writeFile(join(root, 'config.json'), JSON.stringify({ user: 'fixture-user', adapters: [{ provider: 'llm-platform', upstreamOrigins: ['https://upstream.example'], urlEnv: 'FIXTURE_PROXY', requiredEnv: 'FIXTURE_REQUIRED' }] }));
    Object.assign(process.env, { HEADROOM_PI_STATE_DIR: root, HEADROOM_PI_INSTANCE: 'fixture', HEADROOM_PROXY_URL: 'http://127.0.0.1:19878', HEADROOM_PI_CONFIG: join(root, 'config.json'), FIXTURE_PROXY: 'http://127.0.0.1:19878', FIXTURE_REQUIRED: '1' });
    headroom({ on: (event, fn) => handlers.set(event, fn), events: { on: () => () => {} }, exec: async () => ({ code: 1, stdout: '' }) });
    // A different child can initialize in this process before this session starts or sends headers.
    process.env.HEADROOM_PI_INSTANCE = 'another-child';
    process.env.FIXTURE_PROXY = 'http://127.0.0.1:19879';
    const ctx = { cwd: root };
    await handlers.get('session_start')({}, ctx);
    const event = { headers: { 'x-headroom-base-url': 'https://upstream.example', Authorization: 'fixture-only' } };
    await handlers.get('before_provider_headers')(event, ctx);
    assert.equal(event.headers['x-headroom-cwd'], root);
    assert.equal(event.headers['x-headroom-user-id'], 'fixture-user');
    assert.equal(event.headers.Authorization, 'fixture-only');
    const direct = { headers: {} };
    await handlers.get('before_provider_headers')(direct, ctx);
    assert.deepEqual(direct.headers, {});
    const withPath = { headers: { 'x-headroom-base-url': 'https://upstream.example/inference/go/v1' } };
    await handlers.get('before_provider_headers')(withPath, ctx);
    assert.equal(withPath.headers['x-headroom-cwd'], root);
    assert.equal(withPath.headers['x-headroom-user-id'], 'fixture-user');
    for (const value of ['https://other.example/inference/go/v1', 'not a url']) {
      const unmatched = { headers: { 'x-headroom-base-url': value } };
      await handlers.get('before_provider_headers')(unmatched, ctx);
      assert.deepEqual(unmatched.headers, { 'x-headroom-base-url': value });
    }
    await handlers.get('session_shutdown')({}, ctx);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in before)) delete process.env[key];
    Object.assign(process.env, before);
    await rm(root, { recursive: true, force: true });
  }
});
