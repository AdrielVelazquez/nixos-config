import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { chmod, lstat, mkdir, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';

const [python, headroom, pi, providerEntry, superpowersEntry, tokenizerCache] = process.argv.slice(2);
const capabilities = JSON.parse(await readFile(process.env.PI_CAPABILITY_FIXTURE, 'utf8'));
const root = await mkdtemp(join(tmpdir(), 'pi-headroom-stack-'));
for (const path of ['home', 'agent', 'project', 'runtime', 'tmp']) await mkdir(join(root, path), { mode: 0o700 });
for (const [name, source] of Object.entries(capabilities.files)) await symlink(source, join(root, 'agent', name));
const blob = JSON.stringify(Array.from({ length: 800 }, (_, index) => ({ index, status: 'active', category: 'synthetic-row', message: `synthetic-sentinel-${index}`, metadata: 'repeat repeat repeat repeat' })), null, 2);
await writeFile(join(root, 'blob.json'), blob);
const calls = [];
const selectedModel = process.env.PI_STACK_MODEL ?? 'claude-sonnet-5-5';
const gateway = createServer(async (req, res) => {
  let raw = ''; for await (const chunk of req) raw += chunk;
  const body = raw ? JSON.parse(raw) : undefined;
  calls.push({ path: req.url, headers: req.headers, body });
  if (req.url.endsWith('/models')) { res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ data: [...new Set([selectedModel, 'claude-sonnet-5-5', 'gpt-6.1-sol', 'gpt-6-luna'])].map(id => ({ id, x_llm_platform: { capabilities: { api: [id.startsWith('claude') ? 'chat_completions' : 'responses'], tools: true, reasoning: true, reasoning_efforts: ['low', 'high', 'xhigh'] } } })) })); }
  const chunk = (delta, finish_reason = null) => ({ id: 'stack-chat', object: 'chat.completion.chunk', created: 1,
    model: body.model, choices: [{ index: 0, delta, finish_reason }] });
  const inference = calls.filter(call => call.body?.messages || call.body?.input);
  let events = inference.length === 1 ? [chunk({ role: 'assistant', tool_calls: [{ index: 0, id: 'stack-call', type: 'function',
    function: { name: 'fixture_blob', arguments: '{}' } }] }), chunk({}, 'tool_calls')]
    : [chunk({ role: 'assistant', content: 'ROUTED' }), chunk({}, 'stop')];
  if (body.input) {
    const response = { id: 'stack-response', object: 'response', created_at: 1, status: 'in_progress', model: body.model, output: [] };
    if (inference.length === 1) {
      const tool = { id: 'stack-fc', type: 'function_call', call_id: 'stack-call', name: 'fixture_blob', arguments: '{}' };
      events = [{ type: 'response.created', response }, { type: 'response.output_item.added', output_index: 0, item: { ...tool, arguments: '' } },
        { type: 'response.function_call_arguments.delta', output_index: 0, item_id: tool.id, delta: '{}' },
        { type: 'response.output_item.done', output_index: 0, item: tool },
        { type: 'response.completed', response: { ...response, status: 'completed', output: [tool], usage: { input_tokens: 20, output_tokens: 3 } } }];
    } else {
      const item = { id: 'stack-msg', type: 'message', role: 'assistant', status: 'in_progress', content: [] };
      const part = { type: 'output_text', text: '', annotations: [] };
      events = [{ type: 'response.created', response }, { type: 'response.output_item.added', output_index: 0, item },
        { type: 'response.content_part.added', output_index: 0, item_id: item.id, content_index: 0, part },
        { type: 'response.output_text.delta', output_index: 0, item_id: item.id, content_index: 0, delta: 'ROUTED' },
        { type: 'response.output_item.done', output_index: 0, item: { ...item, status: 'completed', content: [{ ...part, text: 'ROUTED' }] } },
        { type: 'response.completed', response: { ...response, status: 'completed', usage: { input_tokens: 20, output_tokens: 3 } } }];
    }
  }
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of events) res.write(`data: ${JSON.stringify(event)}\n\n`);
  res.end(body.input ? '' : 'data: [DONE]\n\n');
});
await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
const upstream = `http://127.0.0.1:${gateway.address().port}`;
const configFile = join(root, 'launcher.json');
await writeFile(configFile, JSON.stringify({ version: 1, piCommand: [pi], proxyCommand: [headroom], port: 0,
  startupTimeout: 60, memory: false, codeGraph: false, user: 'fixture',
  tuningEnv: { HEADROOM_MODE: 'cache', HEADROOM_DISABLE_KOMPRESS: '1', HEADROOM_TELEMETRY: 'off', HEADROOM_OUTPUT_SHAPER: '0' },
  upstreamOrigins: [upstream], adapters: [{ provider: 'llm-platform', urlEnv: 'LLM_PLATFORM_INFERENCE_PROXY_URL', requiredEnv: 'LLM_PLATFORM_INFERENCE_PROXY_REQUIRED', upstreamOrigins: [upstream] }] }));
await writeFile(join(root, 'routing.ts'), `import { createRouting } from ${JSON.stringify(resolve('dotfiles/pi/extensions/routing.ts'))};
export default pi => createRouting(pi, {autoTitle:true, agents:{plan:{model:'llm-platform/claude-sonnet-5-5',thinking:'xhigh'},build:{model:'llm-platform/gpt-6.1-sol',thinking:'high'},title:{model:'llm-platform/gpt-6-luna',thinking:'low'}}});`);
const settings = JSON.stringify({ defaultProvider: 'llm-platform', defaultModel: 'claude-sonnet-5-5',
  retry: { enabled: false }, compaction: { enabled: false, keepRecentTokens: 0 },
  extensions: [providerEntry, resolve('dotfiles/pi/extensions/headroom.ts'), resolve('tests/pi/blob.ts'), join(root, 'routing.ts'), ...(superpowersEntry ? [superpowersEntry] : []), ...Object.values(capabilities.entries)] });
await writeFile(join(root, 'managed-settings.json'), settings); await chmod(join(root, 'managed-settings.json'), 0o444);
await symlink(join(root, 'managed-settings.json'), join(root, 'agent/settings.json'));
await writeFile(join(root, 'agent/mcp.json'), JSON.stringify({ mcpServers: { headroom: { command: headroom, args: ['mcp', 'serve'],
  env: { HEADROOM_PROXY_URL: '${HEADROOM_PROXY_URL}' }, toolExposure: { headroom_stats: 'direct' } } } }));
const env = { PATH: process.env.PATH, HOME: join(root, 'home'), XDG_RUNTIME_DIR: join(root, 'runtime'),
  TMPDIR: join(root, 'tmp'), XDG_CONFIG_HOME: join(root, 'home/.config'), PI_CODING_AGENT_DIR: join(root, 'agent'),
  PI_OFFLINE: '1', PI_TELEMETRY: '0', NO_COLOR: '1', USER: 'fixture', LLM_PLATFORM_PROJECT_ID: 'stack-test',
  LLM_PLATFORM_DEV_BASE_URL: upstream, PI_STACK_STATE: join(root, 'state.json'), PI_STACK_BLOB: join(root, 'blob.json'),
  HF_HUB_OFFLINE: '1', TRANSFORMERS_OFFLINE: '1' };
env.HEADROOM_DISABLE_KOMPRESS = '1';
if (tokenizerCache) env.TIKTOKEN_CACHE_DIR = tokenizerCache;
const child = spawn(python, ['-E', resolve('packages/headroom-pi.py'), '--config', configFile, '--', '--mode', 'rpc', '--offline',
  '--no-approve', '--no-context-files', '--model', `llm-platform/${selectedModel}`], { env, cwd: join(root, 'project'), stdio: ['pipe', 'pipe', 'pipe'] });
let buffer = '', stderr = '', next = 0;
const replies = new Map(), idle = new Set(), events = [];
child.stderr.on('data', data => { stderr += data; });
child.stdout.on('data', data => {
  buffer += data;
  let end;
  while ((end = buffer.indexOf('\n')) >= 0) {
    const line = buffer.slice(0, end).replace(/\r$/, ''); buffer = buffer.slice(end + 1);
    let event;
    try { event = JSON.parse(line); } catch { throw new Error('Non-JSON Pi output: ' + line); }
    events.push(event);
    if (event.type === 'response' && replies.has(event.id)) { replies.get(event.id)(event); replies.delete(event.id); }
    if (event.type === 'agent_settled') { for (const done of idle) done(); idle.clear(); }
  }
});
async function request(command, waitForIdle = false) {
  const id = String(++next);
  const settled = waitForIdle ? new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('Pi did not settle: ' + stderr)), 60000);
    idle.add(() => { clearTimeout(timeout); resolve(); });
  }) : undefined;
  const response = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('RPC timeout: ' + stderr)), 70000);
    replies.set(id, response => { clearTimeout(timeout); resolve(response); });
    child.stdin.write(JSON.stringify({ ...command, id }) + '\n');
  });
  assert.equal(response.success, true, response.error ?? JSON.stringify(response));
  if (settled) await settled;
  return response;
}
try {
  await request({ type: 'prompt', message: 'Use fixture_blob once, then reply ROUTED.' }, true);
  assert.deepEqual(events.filter(event => event.type === 'extension_error'), [], 'normal inference emitted extension errors');
  const state = JSON.parse(await readFile(join(root, 'state.json'), 'utf8'));
  assert.equal(state.ccrVerified, true, 'native Headroom MCP compression/retrieval was not exercised');
  const inference = calls.filter(call => call.body?.messages || call.body?.input);
  assert.ok(inference.length >= 2, JSON.stringify({ calls, stderr }));
  const composedTools = inference[0].body.tools.map(tool => tool.name ?? tool.function?.name);
  for (const name of ['ast_grep_run', 'fetch_content', 'get_search_content']) assert.ok(composedTools.includes(name), `Headroom composition missing ${name}`);
  assert.ok(!composedTools.includes('ast_grep_rewrite'));
  for (const call of inference) {
    assert.equal(call.path, call.body.model.startsWith('gpt') ? '/v1/openai/responses' : '/v1/openai/chat/completions');
    assert.equal(call.headers.authorization, 'Bearer project/stack-test');
    assert.ok(!Object.keys(call.headers).some(header => header.startsWith('x-headroom-')), JSON.stringify(call.headers));
  }
  const compressed = JSON.stringify(inference[1].body.messages ? inference[1].body.messages.filter(message => message.role === 'tool')
    : inference[1].body.input.filter(item => item.type === 'function_call_output'));
  assert.ok(compressed.length < blob.length / 2, `tool output did not compress: ${compressed.length}/${blob.length}`);
  const stats = await (await fetch(state.url + '/stats')).json();
  const title = inference.find(call => call.body.model === 'gpt-6-luna');
  assert.ok(title, 'auxiliary title was not generated through the proxy');
  assert.equal(title.body.reasoning?.effort, 'low');
  const marker = compressed.match(/<<ccr:([a-zA-Z0-9_-]+)>>/);
  if (marker) {
    const response = await fetch(state.url + '/v1/retrieve', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ hash: marker[1] }) });
    const retrieved = await response.json();
    assert.match(JSON.stringify(retrieved), /synthetic-sentinel-799/);
  }
  await request({ type: 'prompt', message: '/llm-platform refresh' });
  await request({ type: 'prompt', message: '/plan' });
  await request({ type: 'prompt', message: 'Reply in plan mode.' }, true);
  assert.equal(calls.at(-1).body.model, 'claude-sonnet-5-5'); assert.equal(calls.at(-1).body.reasoning_effort, 'xhigh');
  await request({ type: 'prompt', message: '/build' });
  await request({ type: 'prompt', message: 'Reply in build mode.' }, true);
  assert.equal(calls.at(-1).body.model, 'gpt-6.1-sol'); assert.equal(calls.at(-1).body.reasoning?.effort, 'high');
  await request({ type: 'set_model', provider: 'llm-platform', modelId: 'gpt-6-luna' });
  await request({ type: 'prompt', message: '/fixture-reload' });
  await request({ type: 'prompt', message: 'Preserve my deliberate model choice.' }, true);
  assert.equal(calls.at(-1).body.model, 'gpt-6-luna');
  assert.ok((await lstat(join(root, 'agent/settings.json'))).isSymbolicLink());
  assert.equal(await readFile(join(root, 'managed-settings.json'), 'utf8'), settings, 'session mode/model choices rewrote managed settings');
  if (superpowersEntry) {
    assert.match(JSON.stringify(inference[0].body), /using-superpowers bootstrap for pi/);
    await request({ type: 'compact' });
    await request({ type: 'prompt', message: 'Reply ROUTED again.' }, true);
    assert.match(JSON.stringify(calls.at(-1).body), /using-superpowers bootstrap for pi/);
    await request({ type: 'prompt', message: '/fixture-reload' });
    await request({ type: 'prompt', message: 'Reply ROUTED after reload.' }, true);
    assert.match(JSON.stringify(calls.at(-1).body), /using-superpowers bootstrap for pi/);
  }
  await request({ type: 'prompt', message: '/llm-platform refresh' });
  assert.ok(calls.some(call => call.path.endsWith('/models')), 'catalog refresh did not reach its trusted control plane');
  await request({ type: 'prompt', message: 'Reply ROUTED after refresh.' }, true);
  assert.ok(calls.at(-1).headers.authorization === 'Bearer project/stack-test');
  const beforeStop = calls.filter(call => call.body?.messages || call.body?.input).length;
  const owned = JSON.parse(await readFile(join(state.root, 'state.json'), 'utf8'));
  process.kill(owned.proxyPid, 'SIGTERM');
  const stopDeadline = Date.now() + 10000;
  while (Date.now() < stopDeadline) {
    try { await fetch(state.url + '/health'); } catch { break; }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  const eventStart = events.length;
  await request({ type: 'prompt', message: 'Reply after the proxy was stopped.' }, true);
  assert.equal(calls.filter(call => call.body?.messages || call.body?.input).length, beforeStop, 'stopped proxy caused direct inference fallback');
  assert.ok(events.slice(eventStart).some(event => event.type === 'message_end' && event.message?.stopReason === 'error'), 'stopped proxy did not surface an inference error');
  assert.deepEqual(events.filter(event => event.type === 'extension_error'), [], 'integration hid an extension failure behind successful inference');
  await writeFile(join(root, 'evidence.json'), JSON.stringify({ inputBytes: blob.length, compressedBytes: compressed.length, marker: marker?.[1], stats, events, stderr }, null, 2));
  console.log(`PASS: real Headroom/Pi routing, auth, automatic compression ${blob.length}→${compressed.length} bytes, native MCP retrieval, exact primary/title routes, deliberate model/reload, refreshed models and stopped-proxy refusal${superpowersEntry ? ', bootstrap/compaction/reload' : ''}`);
  console.log('Evidence: ' + root);
} catch (error) {
  await writeFile(join(root, 'failure.json'), JSON.stringify({ calls, events, stderr }, null, 2));
  try {
    const state = JSON.parse(await readFile(join(root, 'state.json'), 'utf8'));
    console.error('HEADROOM_LOG', (await readFile(join(state.root, 'proxy.log'), 'utf8')).slice(-6000));
    console.error('HEADROOM_STATS', JSON.stringify(await (await fetch(state.url + '/stats')).json()));
  } catch (diagnostic) { console.error('HEADROOM_DIAGNOSTIC', String(diagnostic)); }
  console.error(JSON.stringify({ stderr, tools: events.filter(event => event.type === 'tool_execution_end').map(event => ({ name: event.toolName, isError: event.isError,
    tail: JSON.stringify(event.result).slice(-250) })), inference: calls.filter(call => call.body?.model).map(call => ({ path: call.path, model: call.body.model,
      input: (call.body.input ?? call.body.messages ?? []).map(item => ({ type: item.type ?? item.role, bytes: JSON.stringify(item).length })) })) }));
  throw error;
} finally {
  child.stdin.end();
  const exited = await Promise.race([new Promise(resolve => child.once('exit', () => resolve(true))), new Promise(resolve => setTimeout(() => resolve(false), 5000))]);
  if (!exited) child.kill('SIGTERM');
  gateway.closeAllConnections(); await new Promise(resolve => gateway.close(resolve));
}
