// Retained N1 real-runtime compatibility gate, made independent of the lab path.
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { access, mkdir, mkdtemp, readFile, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';

const [pi, packageRoot, providerEntry, python, headroom] = process.argv.slice(2);
const capabilities = JSON.parse(await readFile(process.env.PI_CAPABILITY_FIXTURE, 'utf8'));
const root = await mkdtemp(join(tmpdir(), 'pi-routing-'));
const agent = join(root, 'agent'), calls = [];
await Promise.all(['home', 'tmp', 'project', 'agent/agents', 'agent/extensions/subagent', 'agent/skills/fixture'].map(path => mkdir(join(root, path), { recursive: true })));
for (const [name, source] of Object.entries(capabilities.files)) await symlink(source, join(agent, name));
await writeFile(join(root, 'project/canary.ts'), 'console.log("CHILD_AST_CANARY");\n');
function stream(res, body) {
  const response = { id: 'fixture-resp', object: 'response', created_at: 1, status: 'in_progress', model: body.model, output: [] };
  const item = { id: 'fixture-msg', type: 'message', role: 'assistant', status: 'in_progress', content: [] };
  const part = { type: 'output_text', text: '', annotations: [] }, output = `SPIKE_OK ${body.model}`;
  let events = [{ type: 'response.created', response }, { type: 'response.output_item.added', output_index: 0, item },
    { type: 'response.content_part.added', item_id: item.id, output_index: 0, content_index: 0, part },
    { type: 'response.output_text.delta', item_id: item.id, output_index: 0, content_index: 0, delta: output },
    { type: 'response.output_item.done', output_index: 0, item: { ...item, status: 'completed', content: [{ ...part, text: output }] } },
    { type: 'response.completed', response: { ...response, status: 'completed', usage: { input_tokens: 20, output_tokens: 3 } } }];
  const transcript = JSON.stringify(body.input ?? body.messages);
  const continued = (body.input ?? []).some(item => item.type === 'function_call_output');
  let tool;
  const probes = {
    MUTATE_PROBE: ['probe_mutate', {}], SHELL_PROBE: ['bash', { command: `touch ${join(root, 'canary')}` }],
    READ_PROBE: ['probe_read', {}], CODEMODE_PROBE: ['codemode', { code: 'return await tools.probe_mutate({});' }],
    MCP_READ_PROBE: ['mcp__fixture__read', {}], MCP_DIRECT_PROBE: ['mcp__fixture__mutate', {}],
    MCP_CODEMODE_PROBE: ['codemode', { code: 'return await tools.mcp__fixture__mutate({});' }],
    MCP_CODEMODE_READ_PROBE: ['codemode', { code: 'return await tools.mcp__fixture__read({});' }],
    NESTED_PROBE: ['subagent', { agent: 'scout', task: 'SIMPLE_NESTED', async: false }],
    NESTED_WRITER_PROBE: ['subagent', { agent: 'build', task: 'FORBIDDEN_WRITER', async: false }],
    STRUCTURAL_READ_WITNESS: ['ast_grep_run', { pattern: 'console.log($ARG)', lang: 'ts', path: 'canary.ts' }],
    STRUCTURAL_WRITE_WITNESS: ['codemode', { code: 'return await tools.ast_grep_rewrite({mode:"pattern",pattern:"console.log($ARG)",rewrite:"console.info($ARG)",path:"canary.ts",lang:"ts",apply:true});' }],
  };
  for (const [marker, [name, args]] of Object.entries(probes)) if (!continued && transcript.includes(marker)) tool = { name, arguments: JSON.stringify(args) };
  if (!continued && transcript.includes('HANG_PROBE')) { res.writeHead(200, { 'Content-Type': 'text/event-stream' }); res.flushHeaders(); return; }
  if (tool) {
    const call = { id: 'fc_fixture', type: 'function_call', call_id: 'call_fixture', ...tool };
    events = [{ type: 'response.created', response }, { type: 'response.output_item.added', output_index: 0, item: { ...call, arguments: '' } },
      { type: 'response.function_call_arguments.delta', item_id: call.id, output_index: 0, delta: tool.arguments },
      { type: 'response.output_item.done', output_index: 0, item: call },
      { type: 'response.completed', response: { ...response, status: 'completed', output: [call], usage: { input_tokens: 20, output_tokens: 3 } } }];
  }
  if (body.model.startsWith('claude')) {
    const chunk = (delta, finish_reason = null) => ({ id: 'fixture-chat', object: 'chat.completion.chunk', created: 1,
      model: body.model, choices: [{ index: 0, delta, finish_reason }] });
    events = [chunk({ role: 'assistant', content: output }), chunk({}, 'stop'), '[DONE]'];
  }
  res.writeHead(200, { 'Content-Type': 'text/event-stream' });
  for (const event of events) res.write(`data: ${typeof event === 'string' ? event : JSON.stringify(event)}\n\n`);
  res.end();
}
const server = createServer(async (req, res) => {
  let raw = ''; for await (const part of req) raw += part;
  const body = raw ? JSON.parse(raw) : undefined;
  calls.push({ path: req.url, body, headers: req.headers });
  if (req.url === '/mcp') {
    if (!body || !('id' in body)) { res.writeHead(202); return res.end(); }
    let result;
    if (body.method === 'initialize') result = { protocolVersion: '2025-11-25', capabilities: { tools: {} }, serverInfo: { name: 'fixture', version: '1' } };
    else if (body.method === 'tools/list') result = { tools: [
      { name: 'read', description: 'Read fixture', inputSchema: { type: 'object', properties: {} }, annotations: { readOnlyHint: true } },
      { name: 'mutate', description: 'Write canary', inputSchema: { type: 'object', properties: {} }, annotations: { destructiveHint: true } }] };
    else if (body.method === 'tools/call') {
      if (body.params.name === 'mutate') await writeFile(join(root, 'canary'), 'MCP_MUTATED');
      result = { content: [{ type: 'text', text: body.params.name === 'read' ? 'MCP_READ_OK' : 'MCP_MUTATED' }] };
    } else result = {};
    res.writeHead(200, { 'Content-Type': 'application/json' }); return res.end(JSON.stringify({ jsonrpc: '2.0', id: body.id, result }));
  }
  if (req.url.endsWith('/models')) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    return res.end(JSON.stringify({ data: ['gpt-6.1-sol', 'gpt-6-luna', 'claude-sonnet-5-5'].map(id => ({ id, x_llm_platform: {
      capabilities: { api: [id.startsWith('claude') ? 'chat_completions' : 'responses'], tools: true, reasoning: true, reasoning_efforts: ['low', 'high', 'xhigh'] },
      limits: { context_window_tokens: 100000, max_output_tokens: 4096 } } })) }));
  }
  if (req.url.endsWith('/responses') || req.url.endsWith('/chat/completions')) return stream(res, body);
  res.writeHead(404); res.end();
});
await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
const base = `http://127.0.0.1:${server.address().port}`;
await writeFile(join(agent, 'settings.json'), JSON.stringify({ defaultProvider: 'llm-platform', defaultModel: 'gpt-6-luna',
  retry: { enabled: false }, compaction: { enabled: false }, subagents: { disableBuiltins: true } }));
await writeFile(join(agent, 'extensions/subagent/config.json'), JSON.stringify({ toolActivation: 'eager', asyncByDefault: false,
  defaultSubagentContext: 'fresh', maxSubagentDepth: 2, intercomBridge: { mode: 'off' } }));
const roles = { scout: ['gpt-6.1-sol', 'low'], explore: ['gpt-6-luna', 'low'], build: ['gpt-6.1-sol', 'high'],
  plan: ['claude-sonnet-5-5', 'xhigh'], title: ['gpt-6-luna', 'low'], invalid: ['missing-model', 'low'] };
for (const [name, [model, thinking]] of Object.entries(roles)) {
  const selected = (capabilities.roles[name]?.match(/^tools: (.*)$/m)?.[1] ?? '').split(', ').filter(tool => tool.startsWith('ast_grep_') || ['fetch_content', 'get_search_content', 'web_search'].includes(tool));
  await writeFile(join(agent, `agents/${name}.md`), `---\nname: ${name}\ndescription: Synthetic role\nmodel: llm-platform/${model}\nthinking: ${thinking}\ntools: read, grep, find, ls, probe_read, codemode, mcp:fixture/read${selected.length ? ', ' + selected.join(', ') : ''}\nextensions: []\ninheritProjectContext: true\ninheritGlobalContext: true\ninheritSkills: true\nacceptance: {"level":"none","reason":"Fixture independently verifies wire and canaries"}\n---\nSynthetic read-only role.\n`);
}
await writeFile(join(agent, 'agents/external.md'), '---\nname: external\ndescription: Must not start\nrunner: {"type":"external-cli","command":"node"}\n---\nDo not run.\n');
await writeFile(join(agent, 'agents/remote.md'), '---\nname: remote\ndescription: Must not contact a machine\nmachine: nonexistent-fixture-host\n---\nDo not run.\n');
await writeFile(join(agent, 'agents/unrequired.md'), '---\nname: unrequired\ndescription: Optional MCP must not leak\nmodel: llm-platform/gpt-6.1-sol\ntools: read, mcp:optional/read\nextensions: []\n---\nMust fail before inference.\n');
await writeFile(join(agent, 'agents/nested.md'), '---\nname: nested\ndescription: Bounded nesting\nmodel: llm-platform/gpt-6.1-sol\nthinking: low\ntools: read, subagent, mcp:fixture/read\nallowNestedSubagents: true\nallowedAgents: scout\nmaxSubagentDepth: 2\nextensions: []\nacceptance: {"level":"none","reason":"Fixture validates lifecycle"}\n---\nDelegate only to scout.\n');
await writeFile(join(agent, 'AGENTS.md'), 'SPIKE_GLOBAL_GUIDANCE\n');
await writeFile(join(root, 'project/AGENTS.md'), 'SPIKE_PROJECT_GUIDANCE\n');
await writeFile(join(agent, 'skills/fixture/SKILL.md'), '---\nname: fixture\ndescription: SPIKE_SKILL_GUIDANCE\n---\nSynthetic skill.\n');
const env = { PATH: process.env.PATH, HOME: join(root, 'home'), XDG_CONFIG_HOME: join(root, 'home/.config'),
  TMPDIR: join(root, 'tmp'), PI_CODING_AGENT_DIR: agent, PI_OFFLINE: '1', PI_TELEMETRY: '0', NO_COLOR: '1',
  LLM_PLATFORM_DEV_BASE_URL: base, LLM_PLATFORM_PROJECT_ID: 'fixture-test',
  LLM_PLATFORM_INFERENCE_PROXY_URL: base, LLM_PLATFORM_INFERENCE_PROXY_REQUIRED: '1', SPIKE_PACKAGE: resolve(packageRoot),
  SPIKE_PROVIDER: resolve(providerEntry), SPIKE_PROBE: resolve('tests/pi/fixtures/routing-probe.ts'),
  SPIKE_RESULT: join(root, 'result.json'), SPIKE_FAILURE: resolve('tests/pi/fixtures/routing-failure.ts'),
  SPIKE_HOLD_GATE: join(root, 'release-children'), SPIKE_HOLD_READY: join(root, 'held-children'),
  SPIKE_ADMISSIONS: join(root, 'admissions.jsonl'), SPIKE_PROXY_CAPTURE: join(root, 'proxy.json'),
  SPIKE_GATEWAY: base, SPIKE_TRACE: join(root, 'trace.jsonl'), SPIKE_CANARY: join(root, 'canary'),
  SPIKE_CAPABILITIES: JSON.stringify(capabilities.required) };
const launchArgs = ['--offline', '--mode', 'rpc', '--no-approve', '--model', 'llm-platform/gpt-6-luna', '-e', join(env.SPIKE_PACKAGE, 'index.js'),
  '-e', env.SPIKE_PROVIDER, '-e', env.SPIKE_PROBE, '-e', resolve('tests/pi/fixtures/routing-optional.ts'), '-e', resolve('tests/pi/fixtures/routing-host.ts')],
  configFile = join(root, 'launcher.json');
for (const entry of Object.values(capabilities.entries)) launchArgs.push('-e', entry);
if (headroom) {
  env.SPIKE_HEADROOM = resolve('dotfiles/pi/extensions/headroom.ts');
  env.XDG_RUNTIME_DIR = join(root, 'runtime'); await mkdir(env.XDG_RUNTIME_DIR, { mode: 0o700 });
  env.HEADROOM_DISABLE_KOMPRESS = '1'; env.HF_HUB_OFFLINE = '1';
  if (process.env.TIKTOKEN_CACHE_DIR) env.TIKTOKEN_CACHE_DIR = process.env.TIKTOKEN_CACHE_DIR;
  launchArgs.push('-e', env.SPIKE_HEADROOM);
  await writeFile(configFile, JSON.stringify({ version: 1, piCommand: [pi], proxyCommand: [headroom], port: 0, startupTimeout: 60,
    memory: false, codeGraph: false, user: 'fixture', tuningEnv: { HEADROOM_MODE: 'cache', HEADROOM_OUTPUT_SHAPER: '0', HEADROOM_TELEMETRY: 'off' },
    upstreamOrigins: [base], adapters: [{ provider: 'llm-platform', urlEnv: 'LLM_PLATFORM_INFERENCE_PROXY_URL', requiredEnv: 'LLM_PLATFORM_INFERENCE_PROXY_REQUIRED' }] }));
}
const child = spawn(headroom ? python : pi, headroom ? ['-E', resolve('packages/headroom-pi.py'), '--config', configFile, '--', ...launchArgs] : launchArgs,
  { env, cwd: join(root, 'project'), stdio: ['pipe', 'pipe', 'pipe'] });
const pending = new Map(), settled = new Set(), events = [];
let buffer = '', stderr = '', counter = 0;
child.stdout.on('data', data => {
  buffer += data;
  let nl;
  while ((nl = buffer.indexOf('\n')) !== -1) {
    const line = buffer.slice(0, nl).replace(/\r$/, ''); buffer = buffer.slice(nl + 1);
    const event = JSON.parse(line); events.push(event);
    if (event.type === 'agent_settled') { for (const done of settled) done(); settled.clear(); }
    const handler = pending.get(event.id);
    if (event.type === 'response' && handler) { pending.delete(event.id); handler(event); }
  }
});
child.stderr.on('data', data => { stderr += data; });
async function command(message, readResult = true) {
  const id = String(++counter);
  const response = await new Promise((resolve, reject) => {
    const timer = setTimeout(() => { pending.delete(id); reject(new Error(`RPC timeout: ${message}; ${stderr}`)); }, 55000);
    pending.set(id, data => { clearTimeout(timer); resolve(data); });
    child.stdin.write(JSON.stringify({ type: 'prompt', id, message }) + '\n');
  });
  assert.equal(response.success, true, JSON.stringify(response));
  return readResult ? JSON.parse(await readFile(env.SPIKE_RESULT, 'utf8')) : response;
}
async function terminal(runId) {
  const deadline = Date.now() + 20000;
  let status;
  do {
    status = await command(`/spike status ${runId}`);
    if (/State: (?:complete|failed|stopped|partial|rejected)/.test(status.data?.text ?? '') && status.data?.details?.lifecycleStatus?.processTerminal?.state === 'observed') return status;
    await new Promise(resolve => setTimeout(resolve, 100));
  } while (Date.now() < deadline);
  throw new Error('async terminal not observed: ' + JSON.stringify(status));
}
try {
  // Native MCP's readiness hooks run on an actual turn, not extension commands.
  const warmup = new Promise((resolve, reject) => { const timer = setTimeout(() => reject(new Error('MCP warmup timeout: ' + stderr)), 15000);
    settled.add(() => { clearTimeout(timer); resolve(); }); });
  child.stdin.write(JSON.stringify({ type: 'prompt', message: 'PARENT_WARMUP' }) + '\n'); await warmup;
  const result = await command('/spike foreground scout SIMPLE');
  assert.equal(result.status, 'completed', JSON.stringify(result)); assert.match(result.result.text, /SPIKE_OK gpt-6\.1-sol/);
  const wire = JSON.stringify(calls.at(-1).body);
  const composedTools = calls.at(-1).body.tools.map(tool => tool.name ?? tool.function?.name);
  for (const name of ['ast_grep_run', 'fetch_content', 'get_search_content', 'web_search']) assert.ok(composedTools.includes(name), `Scout composition missing ${name}`);
  assert.ok(!composedTools.includes('ast_grep_rewrite'));
  const structural = await command('/spike foreground scout STRUCTURAL_READ_WITNESS');
  assert.equal(structural.status, 'completed');
  assert.match(calls.filter(call => call.body?.model).at(-1).body.input.find(item => item.type === 'function_call_output').output, /CHILD_AST_CANARY/);
  assert.equal((await command('/spike foreground scout STRUCTURAL_WRITE_WITNESS')).status, 'completed');
  assert.equal(await readFile(join(root, 'project/canary.ts'), 'utf8'), 'console.log("CHILD_AST_CANARY");\n');
  for (const text of ['SPIKE_GLOBAL_GUIDANCE', 'SPIKE_PROJECT_GUIDANCE', 'SPIKE_SKILL_GUIDANCE']) assert.ok(wire.includes(text), text);
  for (const [role, [model, thinking]] of Object.entries(roles).filter(([role]) => !['invalid', 'scout'].includes(role))) {
    const routed = await command(`/spike foreground ${role} SIMPLE`); assert.equal(routed.status, 'completed', JSON.stringify(routed));
    assert.equal(calls.at(-1).body.model, model); assert.equal(calls.at(-1).body.reasoning?.effort ?? calls.at(-1).body.reasoning_effort, thinking);
  }
  for (const marker of ['READ_PROBE', 'MUTATE_PROBE', 'SHELL_PROBE', 'CODEMODE_PROBE', 'MCP_READ_PROBE', 'MCP_DIRECT_PROBE', 'MCP_CODEMODE_PROBE', 'MCP_CODEMODE_READ_PROBE']) {
    const before = calls.length, probe = await command(`/spike foreground scout ${marker}`);
    assert.equal(probe.status, 'completed', JSON.stringify(probe)); assert.ok(calls.length >= before + 2, marker);
    const output = calls.filter(call => call.body?.model).at(-1).body.input.find(item => item.type === 'function_call_output')?.output;
    if (marker === 'READ_PROBE') assert.equal(output, 'READ_OK');
    if (marker === 'CODEMODE_PROBE') assert.match(output, /probe_mutate does not exist/);
    if (['MCP_READ_PROBE', 'MCP_CODEMODE_READ_PROBE'].includes(marker)) assert.match(output, /MCP_READ_OK/);
    if (marker === 'MCP_CODEMODE_PROBE') assert.match(output, /mutate.*(?:does not exist|not callable|not available)/i);
    await assert.rejects(access(env.SPIKE_CANARY));
  }
  for (const [mode, role, error] of [['foreground', 'invalid', /Unknown subagent model/], ['foreground', 'unrequired', /servers that extensions registered/],
    ['failrequired', 'scout', /required|intentional/i], ['ceiling', 'scout', /required|extension/i]]) {
    const before = calls.filter(call => call.body?.model).length, rejected = await command(`/spike ${mode} ${role} SIMPLE`);
    assert.notEqual(rejected.status, 'completed'); assert.match(rejected.error, error); assert.equal(calls.filter(call => call.body?.model).length, before);
  }
  for (const role of ['external', 'remote']) {
    const before = calls.filter(call => call.body?.model).length, rejected = await command(`/spike async ${role} SIMPLE`);
    assert.equal(rejected.success, false); assert.match(rejected.error.message, /host requires child extensions/);
    assert.equal(calls.filter(call => call.body?.model).length, before);
  }
  const nestedBefore = calls.filter(call => call.body?.model).length;
  assert.equal((await command('/spike foreground nested NESTED_PROBE')).status, 'completed');
  assert.ok(calls.filter(call => call.body?.model).length >= nestedBefore + 3);
  const writerBefore = calls.filter(call => call.body?.model).length;
  assert.equal((await command('/spike foreground nested NESTED_WRITER_PROBE')).status, 'completed');
  assert.equal(calls.filter(call => call.body?.model).length, writerBefore + 2);
  const asyncResult = await command('/spike async scout MCP_CODEMODE_READ_PROBE ASYNC'); assert.equal(asyncResult.success, true);
  const runId = asyncResult.data.details.runId ?? asyncResult.data.details.asyncId; assert.equal(typeof runId, 'string');
  const status = await terminal(runId); assert.match(status.data.text, /State: complete/);
  const asyncFile = JSON.parse(await readFile(join(dirname(asyncResult.data.details.asyncDir), '../async-subagent-results', `${runId}.json`), 'utf8'));
  assert.equal(asyncFile.success, true); assert.match(asyncFile.results[0].output, /SPIKE_OK gpt-6\.1-sol/);
  assert.deepEqual(asyncFile.results[0].launchResolvedExtensions.required, ['provider', 'probe', ...(headroom ? ['headroom'] : []), ...capabilities.required.map(entry => entry.id)]);
  const resumed = await command(`/spike resume ${runId} RESUME_PROBE`); assert.equal(resumed.success, true, JSON.stringify(resumed));
  assert.match((await terminal(resumed.data?.details?.runId ?? runId)).data.text, /State: complete/);
  const hanging = await command('/spike async scout HANG_PROBE'); assert.equal(hanging.success, true);
  const until = Date.now() + 10000;
  while (!calls.some(call => call.body?.model && JSON.stringify(call.body.input ?? call.body.messages).includes('HANG_PROBE')) && Date.now() < until) await new Promise(resolve => setTimeout(resolve, 50));
  assert.equal((await command(`/spike stop ${hanging.data.details.runId}`)).success, true);
  assert.doesNotMatch((await terminal(hanging.data.details.runId)).data.text, /State: complete/);
  const allowedPaths = headroom ? ['/v1/openai/responses', '/v1/openai/chat/completions'] : ['/v1/responses', '/v1/chat/completions'];
  assert.ok(calls.filter(call => call.body?.model).every(call => allowedPaths.includes(call.path)), 'child bypassed recording proxy');
  if (headroom) assert.ok(calls.filter(call => call.body?.model).every(call => !Object.keys(call.headers).some(header => header.startsWith('x-headroom-'))), 'proxy control headers escaped upstream');
  if (headroom) {
    const admissions = async () => (await readFile(env.SPIKE_ADMISSIONS, 'utf8')).trim().split('\n').filter(Boolean).map(line => JSON.parse(line));
    const count = (await admissions()).length;
    await command('/holdchildren', false);
    const rpc = await command('/spike async scout PARENT_EXIT_RPC'); assert.equal(rpc.success, true);
    await command('/run scout PARENT_EXIT_SLASH --bg', false);
    const deadline = Date.now() + 20000;
    let admitted;
    while (Date.now() < deadline) {
      admitted = (await admissions()).slice(count);
      if (admitted.length >= 2) break;
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    assert.ok(admitted.length >= 2, 'slash/RPC launches were not admitted');
    while (Date.now() < deadline) {
      try { if ((await readFile(env.SPIKE_HOLD_READY, 'utf8')).trim()) break; } catch {}
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    const proxy = JSON.parse(await readFile(env.SPIKE_PROXY_CAPTURE, 'utf8'));
    const parentExited = new Promise((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('parent did not exit after stdin closed')), 10000);
      child.once('exit', () => { clearTimeout(timer); resolve(); });
    }); child.stdin.end(); await parentExited;
    for (let attempt = 0; attempt < 10; attempt++) {
      assert.equal((await fetch(proxy.url + '/health')).status, 200, 'admitted slash/RPC children lost their proxy after parent exit');
      await new Promise(resolve => setTimeout(resolve, 50));
    }
    await writeFile(env.SPIKE_HOLD_GATE, 'release');
    const completionDeadline = Date.now() + 30000;
    for (const run of admitted) {
      let status;
      while (Date.now() < completionDeadline) {
        try { status = JSON.parse(await readFile(join(run.asyncDir, 'status.json'), 'utf8')); } catch {}
        if (['complete', 'failed', 'stopped', 'partial', 'rejected'].includes(status?.state)) break;
        await new Promise(resolve => setTimeout(resolve, 50));
      }
      assert.equal(status?.state, 'complete', JSON.stringify(status));
    }
    console.log('PASS: actual slash/RPC admissions survive parent exit before child initialization and complete through Headroom');
  }
  console.log('PASS: packaged five-role routing, inherited instructions/skills, foreground/background/nested/resume/cancel, native MCP and write canaries, strict model/runner/required-extension errors');
} finally {
  await writeFile(env.SPIKE_HOLD_GATE, 'release');
  await writeFile(join(root, 'evidence.json'), JSON.stringify({ calls, events, stderr }, null, 2));
  console.log('Evidence: ' + root);
  child.stdin.end();
  const exited = child.exitCode !== null || child.signalCode !== null || await Promise.race([new Promise(resolve => child.once('exit', () => resolve(true))), new Promise(resolve => setTimeout(() => resolve(false), 3000))]);
  if (!exited) child.kill('SIGTERM'); server.closeAllConnections(); await new Promise(resolve => server.close(resolve));
}
