import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readdir, readFile, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const [python, headroom, pi, tokenizerCache] = process.argv.slice(2);
const urlEnv = 'HEADROOM_PI_PROVIDERS_PROXY_URL', requiredEnv = 'HEADROOM_PI_PROVIDERS_PROXY_REQUIRED';
const root = await mkdtemp(join(tmpdir(), 'pi-headroom-providers-'));
for (const path of ['home', 'agent', 'agent-direct', 'project', 'runtime', 'tmp']) await mkdir(join(root, path), { mode: 0o700 });

const calls = [];
const gateway = createServer(async (req, res) => {
  let raw = ''; for await (const chunk of req) raw += chunk;
  calls.push({ method: req.method, path: req.url, headers: req.headers, body: raw ? JSON.parse(raw) : undefined });
  if (req.method !== 'POST' || req.url !== '/inference/go/v1/chat/completions') { res.writeHead(404); return res.end(); }
  const chunk = (delta, finish_reason = null) => ({ id: 'providers-chat', object: 'chat.completion.chunk', created: 1,
    model: calls.at(-1).body.model, choices: [{ index: 0, delta, finish_reason }] });
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of [chunk({ role: 'assistant', content: 'ROUTED' }), chunk({}, 'stop')]) res.write(`data: ${JSON.stringify(event)}\n\n`);
  res.end('data: [DONE]\n\n');
});
await new Promise(resolveListen => gateway.listen(0, '127.0.0.1', resolveListen));
const origin = `http://127.0.0.1:${gateway.address().port}`;
const upstream = `${origin}/inference/go/v1`;
const inferenceCalls = () => calls.filter(call => call.body?.messages);

await writeFile(join(root, 'launcher.json'), JSON.stringify({ version: 1, piCommand: [pi], proxyCommand: [headroom], port: 0,
  startupTimeout: 60, memory: false, codeGraph: false, user: 'fixture',
  tuningEnv: { HEADROOM_MODE: 'cache', HEADROOM_DISABLE_KOMPRESS: '1', HEADROOM_TELEMETRY: 'off', HEADROOM_OUTPUT_SHAPER: '0' },
  upstreamOrigins: [origin], adapters: [{ provider: 'pi-providers', urlEnv, requiredEnv, upstreamOrigins: [origin] }] }));
const entry = join(root, 'providers.ts');
await writeFile(entry, `import { routeProvidersThroughHeadroom } from ${JSON.stringify(resolve('dotfiles/pi/extensions/headroom-providers.ts'))};
export default pi => routeProvidersThroughHeadroom(pi, ${JSON.stringify({ routes: { 'opencode-go': upstream }, urlEnv, requiredEnv })});`);
const settings = extensions => JSON.stringify({ defaultProvider: 'opencode-go', defaultModel: 'glm-5.3', defaultThinkingLevel: 'high',
  retry: { enabled: false }, compaction: { enabled: false, keepRecentTokens: 0 }, extensions });
await writeFile(join(root, 'agent/settings.json'), settings([resolve('dotfiles/pi/extensions/headroom.ts'), entry]));
await writeFile(join(root, 'agent-direct/settings.json'), settings([entry]));
// Without the extension's refusal this session would reach the gateway directly: models.json points the
// built-in provider at it, and extension registrations are applied on top of models.json.
await writeFile(join(root, 'agent-direct/models.json'), JSON.stringify({ providers: { 'opencode-go': { baseUrl: upstream } } }));

const baseEnv = { PATH: process.env.PATH, HOME: join(root, 'home'), XDG_RUNTIME_DIR: join(root, 'runtime'), TMPDIR: join(root, 'tmp'),
  XDG_CONFIG_HOME: join(root, 'home/.config'), PI_OFFLINE: '1', PI_TELEMETRY: '0', NO_COLOR: '1', USER: 'fixture',
  OPENCODE_API_KEY: 'fixture-key', HF_HUB_OFFLINE: '1', TRANSFORMERS_OFFLINE: '1', HEADROOM_DISABLE_KOMPRESS: '1' };
if (tokenizerCache) baseEnv.TIKTOKEN_CACHE_DIR = tokenizerCache;
const piArgs = ['--mode', 'rpc', '--offline', '--no-approve', '--no-context-files', '--model', 'opencode-go/glm-5.3'];

function start(command, args, env) {
  const child = spawn(command, args, { env: { ...baseEnv, ...env }, cwd: join(root, 'project'), stdio: ['pipe', 'pipe', 'pipe'] });
  const session = { child, events: [], stderr: '' };
  const replies = new Map(), idle = new Set();
  let buffer = '', next = 0;
  child.stderr.on('data', data => { session.stderr += data; });
  child.stdout.on('data', data => {
    buffer += data;
    let end;
    while ((end = buffer.indexOf('\n')) >= 0) {
      const line = buffer.slice(0, end).replace(/\r$/, ''); buffer = buffer.slice(end + 1);
      let event;
      try { event = JSON.parse(line); } catch { throw new Error('Non-JSON Pi output: ' + line); }
      session.events.push(event);
      if (event.type === 'response' && replies.has(event.id)) { replies.get(event.id)(event); replies.delete(event.id); }
      if (event.type === 'agent_settled') { for (const done of idle) done(); idle.clear(); }
    }
  });
  session.prompt = async message => {
    const id = String(++next);
    const settled = new Promise((resolveSettled, reject) => {
      const timeout = setTimeout(() => reject(new Error('Pi did not settle: ' + session.stderr)), 60000);
      idle.add(() => { clearTimeout(timeout); resolveSettled(); });
    });
    const response = await new Promise((resolveReply, reject) => {
      const timeout = setTimeout(() => reject(new Error('RPC timeout: ' + session.stderr)), 70000);
      replies.set(id, reply => { clearTimeout(timeout); resolveReply(reply); });
      child.stdin.write(JSON.stringify({ type: 'prompt', message, id }) + '\n');
    });
    assert.equal(response.success, true, response.error ?? JSON.stringify(response));
    await settled;
  };
  session.stop = async () => {
    child.stdin.end();
    const exited = await Promise.race([new Promise(resolveExit => child.once('exit', () => resolveExit(true))), new Promise(resolveExit => setTimeout(() => resolveExit(false), 5000))]);
    if (!exited) child.kill('SIGTERM');
  };
  return session;
}
const errored = (session, from) => session.events.slice(from).some(event => event.type === 'message_end' && event.message?.stopReason === 'error');

const managed = start(python, ['-E', resolve('packages/headroom-pi.py'), '--config', join(root, 'launcher.json'), '--', ...piArgs],
  { PI_CODING_AGENT_DIR: join(root, 'agent') });
let direct;
try {
  await managed.prompt('Reply ROUTED.');
  assert.deepEqual(managed.events.filter(event => event.type === 'extension_error'), [], 'normal inference emitted extension errors');
  assert.equal(inferenceCalls().length, 1, JSON.stringify({ calls, stderr: managed.stderr }));
  const [call] = inferenceCalls();
  assert.equal(call.path, '/inference/go/v1/chat/completions');
  assert.equal(call.headers.authorization, 'Bearer fixture-key');
  assert.equal(call.body.model, 'glm-5.3');
  // Pi's catalog selects the legacy max_tokens field for these models; Headroom renames it to
  // max_completion_tokens. A gateway that ignores the new field would silently lose the output cap,
  // so a change here needs a live recheck (see TODO.md).
  assert.equal(call.body.max_tokens, undefined);
  assert.equal(typeof call.body.max_completion_tokens, 'number', JSON.stringify(Object.keys(call.body).sort()));
  assert.equal(call.body.reasoning_effort, 'high');
  assert.ok(!Object.keys(call.headers).some(header => header.startsWith('x-headroom-')), JSON.stringify(call.headers));
  const unrouted = calls.filter(other => other !== call);
  assert.deepEqual(unrouted, [], 'unexpected non-inference traffic reached the gateway');

  // A Go model may speak the OpenAI Responses, Anthropic or Google protocol instead. Each must reach the gateway at
  // the path Pi's catalog gives it when it is not routed: a doubled /v1 is answered with an empty-body 404.
  const protocols = [
    ['gpt-6-luna', /^\/inference\/go\/v1\/responses$/],
    ['minimax-m3', /^\/inference\/go\/v1\/messages(\?|$)/],
    ['gemini-4-argon-contributor', /^\/inference\/go\/v1\/models\/gemini-4-argon-contributor:streamGenerateContent/],
  ];
  for (const [id, path] of protocols) {
    const seenBefore = calls.length;
    const other = start(python, ['-E', resolve('packages/headroom-pi.py'), '--config', join(root, 'launcher.json'), '--', ...piArgs.slice(0, -2), '--model', `opencode-go/${id}`],
      { PI_CODING_AGENT_DIR: join(root, 'agent') });
    try { await other.prompt(`Reply ROUTED (${id}).`); } finally { await other.stop(); }
    const seen = calls.slice(seenBefore);
    assert.equal(seen.length, 1, `${id}: ${JSON.stringify(seen.map(entry => entry.path))}`);
    assert.equal(seen[0].method, 'POST');
    assert.match(seen[0].path, path, `${id} reached the gateway at the wrong path`);
    assert.ok(!Object.keys(seen[0].headers).some(header => header.startsWith('x-headroom-')), `${id}: ${JSON.stringify(seen[0].headers)}`);
  }

  const base = join(root, 'runtime', `headroom-pi-${process.getuid()}`);
  const [signature] = await readdir(base);
  const owned = JSON.parse(await readFile(join(base, signature, 'state.json'), 'utf8'));
  process.kill(owned.proxyPid, 'SIGTERM');
  const deadline = Date.now() + 10000;
  while (Date.now() < deadline) {
    try { await fetch(`http://127.0.0.1:${owned.port}/health`); } catch { break; }
    await new Promise(resolveWait => setTimeout(resolveWait, 50));
  }
  const before = inferenceCalls().length, from = managed.events.length;
  await managed.prompt('Reply after the proxy was stopped.');
  assert.equal(inferenceCalls().length, before, 'stopped proxy caused direct inference fallback');
  assert.ok(errored(managed, from), 'stopped proxy did not surface an inference error');

  direct = start(pi, piArgs, { PI_CODING_AGENT_DIR: join(root, 'agent-direct') });
  const directFrom = direct.events.length;
  await direct.prompt('Reply without the launcher.');
  assert.equal(inferenceCalls().length, before, 'Pi without the launcher reached the upstream directly');
  assert.ok(errored(direct, directFrom), 'Pi without the launcher did not surface an inference error');
  console.log('PASS: built-in provider routed through the real Headroom proxy (path, auth, no control headers), stopped-proxy refusal, launcher-less refusal');
} catch (error) {
  await writeFile(join(root, 'failure.json'), JSON.stringify({ calls, managed: managed.events, direct: direct?.events, stderr: managed.stderr, directStderr: direct?.stderr }, null, 2));
  console.error('Evidence: ' + join(root, 'failure.json'));
  throw error;
} finally {
  await managed.stop(); await direct?.stop();
  gateway.closeAllConnections(); await new Promise(resolveClose => gateway.close(resolveClose));
}
