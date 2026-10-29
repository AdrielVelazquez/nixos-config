import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { zstdDecompressSync } from 'node:zlib';
import { createRequire } from 'node:module';
import { mkdir, mkdtemp, readdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const [python, proxyCommand, pi, tokenizerCache] = process.argv.slice(2);
const { WebSocketServer } = createRequire(join(process.env.PI_TEST_PACKAGE_DIR, 'package.json'))('ws');
const root = await mkdtemp(join(tmpdir(), 'pi-headroom-codex-'));
for (const name of ['home', 'project', 'runtime', 'tmp']) await mkdir(join(root, name), { mode: 0o700 });
const calls = [];
function responseEvents(body) {
  const response = { id: 'codex-fixture', object: 'response', created_at: 1, status: 'in_progress', model: body.model, output: [] };
  const item = { id: 'codex-msg', type: 'message', role: 'assistant', status: 'in_progress', content: [] };
  const part = { type: 'output_text', text: '', annotations: [] };
  return [
    { type: 'response.created', response },
    { type: 'response.output_item.added', output_index: 0, item },
    { type: 'response.content_part.added', output_index: 0, item_id: item.id, content_index: 0, part },
    { type: 'response.output_text.delta', output_index: 0, item_id: item.id, content_index: 0, delta: 'ROUTED' },
    { type: 'response.output_item.done', output_index: 0, item: { ...item, status: 'completed', content: [{ ...part, text: 'ROUTED' }] } },
    { type: 'response.completed', response: { ...response, status: 'completed', usage: { input_tokens: 20, output_tokens: 3 } } },
  ];
}
const gateway = createServer(async (req, res) => {
  const chunks = []; for await (const chunk of req) chunks.push(chunk);
  if (req.method !== 'POST' || req.url !== '/backend-api/codex/responses') { res.writeHead(404); return res.end(); }
  const raw = Buffer.concat(chunks);
  const body = JSON.parse((req.headers['content-encoding'] === 'zstd' ? zstdDecompressSync(raw) : raw).toString());
  calls.push({ transport: 'sse', path: req.url, headers: req.headers, body });
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of responseEvents(body)) res.write(`data: ${JSON.stringify(event)}\n\n`);
  res.end();
});
const websocket = new WebSocketServer({ noServer: true });
gateway.on('upgrade', (req, socket, head) => {
  assert.equal(req.url, '/backend-api/codex/responses');
  websocket.handleUpgrade(req, socket, head, ws => {
    ws.on('message', data => {
      const body = JSON.parse(data.toString());
      assert.equal(body.type, 'response.create');
      calls.push({ transport: 'websocket', path: req.url, headers: req.headers, body });
      for (const event of responseEvents(body)) ws.send(JSON.stringify(event));
    });
  });
});
await new Promise(done => gateway.listen(0, '127.0.0.1', done));
const origin = `http://127.0.0.1:${gateway.address().port}`;
const token = 'fixture.' + Buffer.from(JSON.stringify({ 'https://api.openai.com/auth': { chatgpt_account_id: 'fixture-account' } })).toString('base64url') + '.fixture';
const urlEnv = 'HEADROOM_PI_CODEX_PROXY_URL', requiredEnv = 'HEADROOM_PI_CODEX_PROXY_REQUIRED';
const manifest = join(root, 'launcher.json');
await writeFile(manifest, JSON.stringify({ version: 1, piCommand: [pi], proxyCommand: [proxyCommand], port: 0,
  startupTimeout: 60, memory: false, codeGraph: false, user: 'fixture-user',
  tuningEnv: { HEADROOM_MODE: 'cache', HEADROOM_DISABLE_KOMPRESS: '1', HEADROOM_TELEMETRY: 'off', HEADROOM_OUTPUT_SHAPER: '0', HEADROOM_OFFLINE: '1' },
  upstreamOrigins: ['https://chatgpt.com'], adapters: [{ provider: 'openai-codex', urlEnv, requiredEnv, upstreamOrigins: ['https://chatgpt.com'] }] }));
const entry = join(root, 'codex.ts');
await writeFile(entry, `import { routeCodexThroughHeadroom } from ${JSON.stringify(resolve('dotfiles/pi/extensions/headroom-codex.ts'))};
export default pi => routeCodexThroughHeadroom(pi, ${JSON.stringify({ urlEnv, requiredEnv })});`);
const env = { PATH: process.env.PATH, HOME: join(root, 'home'), XDG_RUNTIME_DIR: join(root, 'runtime'), TMPDIR: join(root, 'tmp'),
  XDG_CONFIG_HOME: join(root, 'home/.config'), PI_OFFLINE: '1', PI_TELEMETRY: '0', NO_COLOR: '1', USER: 'fixture',
  PI_CODEX_FIXTURE_ORIGIN: origin, TIKTOKEN_CACHE_DIR: tokenizerCache, HF_HUB_OFFLINE: '1', TRANSFORMERS_OFFLINE: '1' };

async function start(name, transport, managed, enabled = true) {
  const dir = join(root, name); await mkdir(dir);
  const extensions = enabled ? [entry] : [];
  if (managed) extensions.unshift(resolve('dotfiles/pi/extensions/headroom.ts'));
  await writeFile(join(dir, 'settings.json'), JSON.stringify({ transport, extensions,
    retry: { enabled: false }, compaction: { enabled: false }, defaultThinkingLevel: 'off' }));
  await writeFile(join(dir, 'auth.json'), JSON.stringify({ 'openai-codex': {
    type: 'oauth', access: token, refresh: 'fixture-refresh', expires: Date.now() + 3600000, accountId: 'fixture-account',
  } }));
  // Without the routing adapter, this model override can reach the fixture directly.
  await writeFile(join(dir, 'models.json'), JSON.stringify({ providers: { 'openai-codex': { baseUrl: origin + '/backend-api' } } }));
  const args = ['--mode', 'rpc', '--offline', '--no-approve', '--no-context-files', '--no-session', '--model', 'openai-codex/gpt-6.1-sol'];
  const child = spawn(managed ? python : pi, managed ? ['-E', resolve('packages/headroom-pi.py'), '--config', manifest, '--', ...args] : args,
    { cwd: join(root, 'project'), env: { ...env, PI_CODING_AGENT_DIR: dir }, stdio: ['pipe', 'pipe', 'pipe'] });
  const session = { child, events: [], stderr: '' };
  let buffer = '', settled;
  child.stderr.on('data', data => { session.stderr += data; });
  child.stdout.on('data', data => {
    buffer += data;
    let end;
    while ((end = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
      let event;
      try { event = JSON.parse(line); } catch { continue; }
      session.events.push(event);
      if (event.type === 'agent_settled') settled?.();
    }
  });
  session.prompt = async () => {
    const from = session.events.length;
    await new Promise((done, reject) => {
      const timer = setTimeout(() => reject(new Error('Pi timeout: ' + session.stderr)), 30000);
      settled = () => { clearTimeout(timer); done(); };
      child.stdin.write(JSON.stringify({ id: 'prompt', type: 'prompt', message: 'Reply ROUTED.' }) + '\n');
    });
    const events = session.events.slice(from);
    assert.deepEqual(events.filter(e => e.type === 'extension_error'), []);
    return events.filter(e => e.type === 'message_end' && e.message?.role === 'assistant').at(-1)?.message;
  };
  session.stop = async () => {
    if (child.exitCode !== null || child.signalCode) return;
    const stopped = new Promise(done => child.once('exit', done));
    child.stdin.end();
    const timer = setTimeout(() => child.kill('SIGTERM'), 3000);
    await stopped; clearTimeout(timer);
  };
  return session;
}
const sessions = [];
try {
  for (const transport of ['sse', 'websocket']) {
    const session = await start('managed-' + transport, transport, true); sessions.push(session);
    const before = calls.length, message = await session.prompt();
    assert.equal(message?.stopReason, 'stop', JSON.stringify({ message, stderr: session.stderr }));
    assert.equal(message.provider, 'openai-codex');
    assert.equal(message.model, 'gpt-6.1-sol');
    assert.equal(message.content.find(part => part.type === 'text')?.text, 'ROUTED');
    assert.equal(calls.length, before + 1, 'exactly one proxied inference');
    const call = calls.at(-1);
    assert.equal(call.transport, transport);
    assert.equal(call.headers.authorization, 'Bearer ' + token);
    assert.equal(call.headers['chatgpt-account-id'], 'fixture-account');
    assert.ok(!Object.keys(call.headers).some(key => key.startsWith('x-headroom-')), 'proxy control headers must not leak upstream');
  }
  const stateRoot = join(root, 'runtime', `headroom-pi-${process.getuid()}`);
  const [signature] = await readdir(stateRoot);
  const state = JSON.parse(await readFile(join(stateRoot, signature, 'state.json'), 'utf8'));
  const stats = await (await fetch(`http://127.0.0.1:${state.port}/stats`)).json();
  assert.ok(stats.requests.total >= 2, 'dashboard must count successful Codex requests: ' + JSON.stringify(stats.requests));
  assert.ok(stats.savings.per_project?.project || stats.agent_usage.agents.length > 0, 'Codex requests must carry project/user attribution');
  for (const transport of ['sse', 'websocket']) {
    const absent = await start('absent-' + transport, transport, false); sessions.push(absent);
    const before = calls.length;
    assert.equal((await absent.prompt())?.stopReason, 'error');
    assert.equal(calls.length, before, 'missing launcher must not reach direct models.json upstream');
    await absent.stop();
  }
  const direct = await start('disabled', 'sse', false, false); sessions.push(direct);
  const beforeDirect = calls.length;
  assert.equal((await direct.prompt())?.stopReason, 'stop', 'disabled routing must preserve native direct OAuth inference');
  assert.equal(calls.length, beforeDirect + 1);
  await direct.stop();
  process.kill(state.proxyPid, 'SIGTERM');
  const deadline = Date.now() + 10000;
  let exited = false;
  while (Date.now() < deadline) {
    try { process.kill(state.proxyPid, 0); } catch { exited = true; break; }
    await new Promise(done => setTimeout(done, 50));
  }
  assert.ok(exited, 'proxy must have exited before testing stopped-proxy refusal');
  for (const session of sessions.slice(0, 2)) {
    const before = calls.length;
    assert.equal((await session.prompt())?.stopReason, 'error');
    assert.equal(calls.length, before, 'stopped proxy must never fall back directly');
  }
  console.log('PASS: real Pi OAuth + real Headroom SSE/WebSocket routing, native provider identity, credentials, dashboard counts, attribution, disabled-direct and fail-closed behavior');
} catch (error) {
  console.error('Fixture: ' + root);
  for (const session of sessions) console.error(session.stderr);
  throw error;
} finally {
  for (const session of sessions) await session.stop();
  for (const client of websocket.clients) client.terminate();
  websocket.close(); gateway.closeAllConnections(); await new Promise(done => gateway.close(done));
}
