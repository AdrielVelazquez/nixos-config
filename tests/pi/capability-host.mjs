// Trusted synthetic model transport. Run only in the Nix check sandbox.
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { lstat, mkdir, readFile, symlink, writeFile } from 'node:fs/promises';
import { createRequire } from 'node:module';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

export async function openHost(spec) {
  assert.ok(process.env.NIX_BUILD_TOP, 'candidate execution belongs in a Nix sandbox');
  const root = join(process.env.TMPDIR, 'capability-test'), cwd = join(root, 'project'), agent = join(root, 'agent');
  await mkdir(cwd, { recursive: true }); await mkdir(agent, { recursive: true }); process.chdir(cwd);
  Object.assign(process.env, { HOME: root, PI_CODING_AGENT_DIR: agent,
    XDG_CONFIG_HOME: join(root, 'config'), XDG_CACHE_HOME: join(root, 'cache'),
    PI_ALLOW_BROWSER_COOKIES: '1', FEYNMAN_ALLOW_BROWSER_COOKIES: '1', AST_GREP_BIN: '/missing/ambient/ast-grep' });
  for (const key of ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'NO_PROXY', 'http_proxy', 'https_proxy', 'all_proxy', 'no_proxy']) delete process.env[key];
  await symlink(spec.settingsFile, join(agent, 'settings.json'));
  for (const [name, file] of Object.entries(spec.files)) await symlink(file, join(agent, name));
  await writeFile(join(cwd, 'canary.ts'), 'console.log("STRUCTURAL_CANARY");\nexport function answer(): number { return 42; }\n');
  await writeFile(join(cwd, 'sgconfig.yml'), 'customLanguages: [invalid hostile project grammar configuration]\n');
  const sdkRoot = process.env.PI_TEST_PACKAGE_DIR;
  const sdk = await import(pathToFileURL(`${sdkRoot}/dist/index.js`).href);
  const { Type } = createRequire(`${sdkRoot}/package.json`)('typebox');
  sdk.initTheme('dark', false);
  let next, session;
  const calls = [], errors = [];
  const gateway = createServer(async (req, res) => {
    let raw = ''; for await (const part of req) raw += part;
    const body = JSON.parse(raw); calls.push(body);
    const chunk = (delta, finish_reason = null) => ({ id: 'fixture', object: 'chat.completion.chunk', created: 1,
      model: 'unit', choices: [{ index: 0, delta, finish_reason }] });
    const data = body.messages.at(-1).role === 'tool'
      ? [chunk({ role: 'assistant', content: 'DONE' }), chunk({}, 'stop')]
      : [chunk({ role: 'assistant', tool_calls: [{ index: 0, id: next.id, type: 'function',
        function: { name: next.name, arguments: JSON.stringify(next.args) } }] }), chunk({}, 'tool_calls')];
    res.writeHead(200, { 'Content-Type': 'text/event-stream' });
    for (const item of data) res.write(`data: ${JSON.stringify(item)}\n\n`);
    res.end('data: [DONE]\n\n');
  });
  await new Promise(resolve => gateway.listen(0, '127.0.0.1', resolve));
  try {
    const settings = sdk.SettingsManager.create(cwd, agent, { projectTrusted: true });
    const runtime = await sdk.ModelRuntime.create({ authPath: join(agent, 'auth.json'), modelsPath: null,
      modelsStorePath: join(agent, 'catalog.json'), refreshOnCreate: false });
    runtime.registerProvider('fixture', { baseUrl: `http://127.0.0.1:${gateway.address().port}/v1`, api: 'openai-completions', apiKey: 'synthetic-only',
      models: [{ id: 'unit', name: 'unit', reasoning: false, input: ['text'], contextWindow: 100000, maxTokens: 1024,
        cost: { input: 0, output: 0, cacheRead: 0, cacheWrite: 0 } }] });
    const loader = new sdk.DefaultResourceLoader({ cwd, agentDir: agent, settingsManager: settings,
      noContextFiles: true, noSkills: true, noPromptTemplates: true,
      disabledBuiltinExtensions: ['mcp', 'tool-search', 'llama'], extensionFactories: [pi => {
        pi.registerTool({ name: 'fixture_nested', label: 'Nested fixture', description: 'Exercise native nested execution',
          parameters: Type.Object({ name: Type.String(), args: Type.Any() }),
          execute: async (_id, input, _signal, _update, ctx) => {
            const result = await ctx.executeTool(input.name, input.args);
            return { content: result.result.content, details: { denied: result.isError } };
          } });
      }] });
    await loader.reload(); assert.deepEqual(loader.getExtensions().errors, []);
    ({ session } = await sdk.createAgentSession({ cwd, agentDir: agent, modelRuntime: runtime, model: runtime.getModel('fixture', 'unit'),
      resourceLoader: loader, settingsManager: settings, sessionManager: sdk.SessionManager.inMemory() }));
    await session.bindExtensions({ mode: 'rpc', onError: error => errors.push(error) });
    assert.deepEqual(errors, []);
    return { sdk, session, cwd, agent, calls, errors,
      async call(name, args) {
        next = { id: `fixture-${calls.length}`, name, args };
        const start = session.messages.length, count = calls.length;
        await session.prompt('Execute the selected synthetic action exactly once.');
        assert.deepEqual(errors, []);
        assert.equal(calls.length - count, 2, 'unexpected side-model calls');
        const result = session.messages.slice(start).find(message => message.role === 'toolResult' && message.toolName === name);
        assert.ok(result, `missing actual tool result: ${name}`);
        return result;
      },
      async immutable() {
        for (const [name, file] of Object.entries({ ...spec.files, 'settings.json': spec.settingsFile })) {
          assert.ok((await lstat(join(agent, name))).isSymbolicLink(), name);
          assert.equal(await readFile(join(agent, name), 'utf8'), await readFile(file, 'utf8'), name);
        }
      },
      async close() {
        await session.extensionRunner.emit({ type: 'session_shutdown', reason: 'quit' }); session.dispose();
        gateway.closeAllConnections(); await new Promise(resolve => gateway.close(resolve));
      } };
  } catch (error) {
    session?.dispose(); gateway.closeAllConnections(); await new Promise(resolve => gateway.close(resolve)); throw error;
  }
}
