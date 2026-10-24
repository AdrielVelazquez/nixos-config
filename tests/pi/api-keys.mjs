import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

const [fixturePath, pi] = process.argv.slice(2);
const f = JSON.parse(await readFile(fixturePath, 'utf8'));
const generated = JSON.parse(await readFile(f.modelsFile, 'utf8'));

assert.deepEqual(Object.keys(generated.providers).sort(), ['opencode', 'opencode-go']);
for (const provider of Object.values(generated.providers)) {
  assert.deepEqual(Object.keys(provider), ['apiKey']);
  assert.ok(provider.apiKey.startsWith('!') && provider.apiKey.includes(f.secretPath), provider.apiKey);
  assert.ok(provider.apiKey.includes('/bin/cat'), 'the key is read with cat from the secret path, never embedded');
}
assert.deepEqual(f.secrets, ['opencode_api_key']);
assert.equal(f.unconfiguredHasModels, false, 'a host without apiKeys must not get a models.json');

const root = await mkdtemp(join(tmpdir(), 'pi-api-keys-'));
for (const path of ['home', 'agent', 'project', 'tmp']) await mkdir(join(root, path), { mode: 0o700 });
const calls = [];
const gateway = createServer(async (req, res) => {
  let raw = ''; for await (const chunk of req) raw += chunk;
  calls.push({ path: req.url, headers: req.headers, body: raw ? JSON.parse(raw) : undefined });
  const chunk = (delta, finish_reason = null) => ({ id: 'api-key-chat', object: 'chat.completion.chunk', created: 1,
    model: calls.at(-1).body?.model, choices: [{ index: 0, delta, finish_reason }] });
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of [chunk({ role: 'assistant', content: 'OK' }), chunk({}, 'stop')]) res.write(`data: ${JSON.stringify(event)}\n\n`);
  res.end('data: [DONE]\n\n');
});
await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
const upstream = `http://127.0.0.1:${gateway.address().port}/inference/go/v1`;
// The generated file supplies only the key command; the test adds the endpoint so no request leaves the sandbox.
await writeFile(join(root, 'agent/models.json'), JSON.stringify({ providers: { 'opencode-go': { ...generated.providers['opencode-go'], baseUrl: upstream } } }));
await writeFile(join(root, 'agent/settings.json'), JSON.stringify({ defaultProvider: 'opencode-go', defaultModel: 'glm-5.3',
  defaultThinkingLevel: 'high', retry: { enabled: false }, compaction: { enabled: false, keepRecentTokens: 0 } }));
const env = { PATH: process.env.PATH, HOME: join(root, 'home'), TMPDIR: join(root, 'tmp'), PI_CODING_AGENT_DIR: join(root, 'agent'),
  PI_OFFLINE: '1', PI_TELEMETRY: '0', NO_COLOR: '1' };

async function session(message) {
  const child = spawn(pi, ['--mode', 'rpc', '--offline', '--no-approve', '--no-context-files', '--model', 'opencode-go/glm-5.3'],
    { env, cwd: join(root, 'project'), stdio: ['pipe', 'pipe', 'pipe'] });
  const events = [];
  let buffer = '', stderr = '';
  child.stderr.on('data', data => { stderr += data; });
  const settled = new Promise(resolve => {
    child.stdout.on('data', data => {
      buffer += data;
      let end;
      while ((end = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0, end).replace(/\r$/, ''); buffer = buffer.slice(end + 1);
        try { events.push(JSON.parse(line)); } catch { continue; }
        const event = events.at(-1);
        if (event.type === 'agent_settled' || (event.type === 'response' && event.success === false)) resolve();
      }
    });
    child.once('exit', () => resolve());
    setTimeout(resolve, 60000);
  });
  child.stdin.write(JSON.stringify({ type: 'prompt', message, id: '1' }) + '\n');
  await settled;
  child.stdin.end();
  await Promise.race([new Promise(resolve => child.once('exit', resolve)), new Promise(resolve => setTimeout(resolve, 5000))]);
  if (child.exitCode === null) child.kill('SIGTERM');
  return { events, stderr };
}
const inference = () => calls.filter(call => call.body?.messages);

try {
  await writeFile(f.secretPath, 'fixture-key\n');
  const signedIn = await session('Reply OK.');
  assert.equal(inference().length, 1, JSON.stringify({ calls, stderr: signedIn.stderr }));
  assert.equal(inference()[0].headers.authorization, 'Bearer fixture-key', 'the key must arrive trimmed, from the secret file');

  await rm(f.secretPath);
  const before = inference().length;
  const signedOut = await session('Reply OK again.');
  assert.equal(inference().length, before, 'without the secret no request may be sent');
  assert.ok(signedOut.events.some(event => (event.type === 'message_end' && event.message?.stopReason === 'error')
    || (event.type === 'response' && event.success === false)) || /key|auth/i.test(signedOut.stderr),
    JSON.stringify({ events: signedOut.events.slice(-4), stderr: signedOut.stderr }));
  console.log('PASS: Pi reads the OpenCode key from the SOPS secret path at run time (trimmed, never embedded) and sends nothing without it');
} finally {
  await rm(f.secretPath, { force: true });
  gateway.closeAllConnections(); await new Promise(resolve => gateway.close(resolve));
}
