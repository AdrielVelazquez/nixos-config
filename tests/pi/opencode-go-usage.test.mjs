import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import { createServer } from 'node:http';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const core = await import(pathToFileURL(resolve(process.env.OPENCODE_GO_USAGE_CORE ?? 'dotfiles/pi/extensions/opencode-go-usage-core.ts')));
const { createOpenCodeGoUsage } = await import(pathToFileURL(resolve('dotfiles/pi/extensions/opencode-go-usage.ts')));

const NOW = Date.parse('2026-11-13T12:00:00.000Z');
const RESET = Date.parse('2026-11-21T12:00:00.000Z');

test('reads the monthly percent and reset time', () => {
  assert.deepEqual(
    core.monthlyUsage({ usage: { monthly: { status: 'ok', percent: 7, resetsAt: '2026-11-21T14:25:08.000Z' } } }),
    { percent: 7, resetsAt: Date.parse('2026-11-21T14:25:08.000Z') },
  );
});

test('ignores missing, malformed or out-of-range monthly data', () => {
  assert.equal(core.monthlyUsage(undefined), undefined);
  assert.equal(core.monthlyUsage({ usage: {} }), undefined);
  assert.equal(core.monthlyUsage({ usage: { monthly: { percent: '7' } } }), undefined);
  assert.equal(core.monthlyUsage({ usage: { monthly: { percent: Number.NaN } } }), undefined);
  assert.deepEqual(core.monthlyUsage({ usage: { monthly: { percent: 140 } } }), { percent: 100, resetsAt: null });
  assert.deepEqual(core.monthlyUsage({ usage: { monthly: { percent: -2 } } }), { percent: 0, resetsAt: null });
});

test('a rate-limited monthly window reads as fully used', () => {
  assert.deepEqual(
    core.monthlyUsage({ usage: { monthly: { status: 'rate-limited', resetsAt: '2026-11-21T12:00:00.000Z' } } }),
    { percent: 100, resetsAt: RESET },
  );
});

test('formats monthly usage with a reset countdown', () => {
  assert.equal(core.formatUsage({ percent: 7, resetsAt: RESET }, NOW), 'Go 7% ↻8d');
  assert.equal(core.formatUsage({ percent: 7, resetsAt: NOW + 3 * 3_600_000 }, NOW), 'Go 7% ↻3h');
  assert.equal(core.formatUsage({ percent: 7, resetsAt: NOW + 45 * 60_000 }, NOW), 'Go 7% ↻45m');
  assert.equal(core.formatUsage({ percent: 7, resetsAt: null }, NOW), 'Go 7%');
  assert.equal(core.formatUsage({ percent: 7, resetsAt: NOW - 1 }, NOW), 'Go 7%');
});

async function startServer(handler) {
  const server = createServer(handler);
  await new Promise((ready, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', ready);
  });
  const { port } = server.address();
  return {
    url: `http://127.0.0.1:${port}/zen/go/v1/usage`,
    close: () => new Promise(done => server.close(done)),
  };
}

function harness() {
  const handlers = new Map();
  const statuses = [];
  const pi = {
    on(name, callback) {
      const list = handlers.get(name) ?? [];
      list.push(callback);
      handlers.set(name, list);
    },
  };
  const ctx = { ui: { setStatus: (key, value) => statuses.push([key, value]) } };
  return {
    pi,
    ctx,
    statuses,
    async emit(name, event = {}) {
      for (const callback of handlers.get(name) ?? []) await callback(event, ctx);
    },
  };
}

function keyFile(t) {
  const dir = mkdtempSync(join(tmpdir(), 'pi-go-usage-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'key');
  writeFileSync(path, 'test-key\n');
  return path;
}

test('shows the monthly usage, sends the key, and refreshes after a turn', async (t) => {
  let percent = 7;
  const requests = [];
  const server = await startServer((request, response) => {
    requests.push({ url: request.url, auth: request.headers.authorization });
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({
      usage: { monthly: { status: 'ok', percent, resetsAt: new Date(Date.now() + 30.5 * 86_400_000).toISOString() } },
    }));
  });
  t.after(server.close);

  const app = harness();
  createOpenCodeGoUsage(app.pi, { keyFile: keyFile(t), url: server.url, minRefreshMs: 0 });
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['opencode-go-usage', 'Go 7% ↻30d']);
  assert.deepEqual(requests, [{ url: '/zen/go/v1/usage', auth: 'Bearer test-key' }]);

  percent = 8;
  await app.emit('agent_end');
  assert.deepEqual(app.statuses.at(-1), ['opencode-go-usage', 'Go 8% ↻30d']);
  assert.equal(requests.length, 2);
});

test('a rejected request shows unavailable instead of failing the session', async (t) => {
  const server = await startServer((_request, response) => {
    response.writeHead(401, { 'content-type': 'application/json' });
    response.end('{}');
  });
  t.after(server.close);

  const app = harness();
  createOpenCodeGoUsage(app.pi, { keyFile: keyFile(t), url: server.url, minRefreshMs: 0 });
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['opencode-go-usage', 'Go —']);
});

test('an unreadable key shows unavailable without a request', async () => {
  const app = harness();
  createOpenCodeGoUsage(app.pi, { keyFile: '/nonexistent/opencode-go-key', minRefreshMs: 0 });
  await app.emit('session_start');
  assert.deepEqual(app.statuses.at(-1), ['opencode-go-usage', 'Go —']);
});

test('refreshes at most once per configured interval', async (t) => {
  let requests = 0;
  const server = await startServer((_request, response) => {
    requests++;
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ usage: { monthly: { percent: 7 } } }));
  });
  t.after(server.close);

  const app = harness();
  createOpenCodeGoUsage(app.pi, { keyFile: keyFile(t), url: server.url, minRefreshMs: 60_000 });
  await app.emit('session_start');
  await app.emit('agent_end');
  assert.equal(requests, 1);
});

test('clears the footer status when the session shuts down', async (t) => {
  const server = await startServer((_request, response) => {
    response.writeHead(200, { 'content-type': 'application/json' });
    response.end(JSON.stringify({ usage: { monthly: { percent: 7 } } }));
  });
  t.after(server.close);

  const app = harness();
  createOpenCodeGoUsage(app.pi, { keyFile: keyFile(t), url: server.url, minRefreshMs: 0 });
  await app.emit('session_start');
  await app.emit('session_shutdown');
  assert.deepEqual(app.statuses.at(-1), ['opencode-go-usage', undefined]);
});
