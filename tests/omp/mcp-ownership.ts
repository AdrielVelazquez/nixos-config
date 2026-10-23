// Runs against the actual patched manager in its native package build environment.
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';


// Bun reports only node:assert frames for a failed rejection, so every expectation names itself.
const rejects = async (label, promise, pattern) => {
  try { await promise; } catch (error) { assert.match(String(error?.message ?? error), pattern, label); return; }
  assert.fail(label + ': expected a rejection');
};

const home = await mkdtemp(join(tmpdir(), 'owned-mcp-'));
process.env.HOME = home;
process.env.PI_CODING_AGENT_DIR = join(home, '.omp/agent');
await mkdir(process.env.PI_CODING_AGENT_DIR, { recursive: true });
// Static imports are hoisted above the environment: resolve the agent directory only after it is set.
const { MCPManager } = await import('../src/mcp/manager');
const { extensionMcpRegistry, checkExtensionMcpCall } = await import('../src/mcp/extension-servers');
const { loadAllMCPConfigs } = await import('../src/mcp/config');
const calls = [];
const server = Bun.serve({ port: 0, hostname: '127.0.0.1', async fetch(request) {
  if (request.method !== 'POST') return new Response(null, { status: 405 });
  const body = await request.json();
  calls.push({ path: new URL(request.url).pathname, ...body });
  if (!('id' in body)) return new Response(null, { status: 202 });
  const result = body.method === 'initialize' ? { protocolVersion: '2025-11-25', capabilities: { tools: {} }, serverInfo: { name: 'ownership', version: '1' } }
    : body.method === 'tools/list' ? { tools: [{ name: 'slack__search', description: 'fixture', inputSchema: { type: 'object', properties: {} } }] }
    : { content: [{ type: 'text', text: 'ownership fixture' }] };
  return Response.json({ jsonrpc: '2.0', id: body.id, result });
} });
const owned = { type: 'http', url: `http://127.0.0.1:${server.port}/owned` };
const explicit = { type: 'http', url: `http://127.0.0.1:${server.port}/explicit` };
const source = { provider: 'mcp-json', providerName: 'Explicit', path: join(home, 'mcp.json'), level: 'project' };
const owner = { path: join(home, 'fixture.ts') };
try {
  if (!process.argv.includes('--disabled')) {
  // A later discovery must detach, not relabel, a retained runtime connection.
  let release;
  const gate = new Promise(resolve => { release = resolve; });
  let discovering = false;
  const manager = new MCPManager(home, undefined, async () => {
    if (!discovering) return { configs: {}, sources: {}, exaApiKeys: [] };
    await gate;
    return { configs: { 'reddit-tools': explicit }, sources: { 'reddit-tools': source }, exaApiKeys: [] };
  });
  const registry = extensionMcpRegistry(manager);
  await registry.register(owner, {}, 'reddit-tools', owned, async () => ({ allow: false, reason: 'OWNED_DENIED' }), () => true);
  await manager.waitForPendingConnections();
  const retained = manager.getConnection('reddit-tools');
  const retainedTool = manager.getTools().find(tool => tool.mcpToolName === 'slack__search');
  const oldSource = retained._source;
  discovering = true;
  const discovery = manager.discoverAndConnect({ startupTimeoutMs: 1000 });
  release();
  await discovery;
  assert.equal(manager.getConnection('reddit-tools').config.url, explicit.url, 'late explicit discovery kept the runtime endpoint');
  assert.equal(retained._source, oldSource, 'retained runtime connection was relabeled');
  await rejects('retained handle guard', checkExtensionMcpCall(retained._source, 'reddit-tools', 'slack__search', home), /active|DENIED/);
  await rejects('retained tool execution', retainedTool.execute('stale-call', {}, undefined, { sessionManager: { getCwd: () => home } }), /active|DENIED/);
  assert.equal(registry.snapshots().find(item => item.name === 'reddit-tools').extensionOwned, false);
  await manager.disconnectAll();

  // Live project-config reconciliation must use the same ownership boundary.
  let project = false;
  const live = new MCPManager(home, undefined, async (_cwd, options) => ({
    configs: options?.enableProjectConfig && project ? { 'reddit-tools': explicit } : {},
    sources: options?.enableProjectConfig && project ? { 'reddit-tools': source } : {}, exaApiKeys: [],
  }));
  await live.discoverAndConnect({ enableProjectConfig: false, startupTimeoutMs: 1000 });
  const liveRegistry = extensionMcpRegistry(live);
  await liveRegistry.register(owner, {}, 'reddit-tools', owned, async () => ({ allow: false }), () => true);
  await live.waitForPendingConnections();
  const stale = live.getConnection('reddit-tools');
  const staleTool = live.getTools().find(tool => tool.mcpToolName === 'slack__search');
  project = true;
  await live.reconcileProjectConfig(true);
  assert.equal(live.getConnection('reddit-tools').config.url, explicit.url);
  await rejects('live stale handle guard', checkExtensionMcpCall(stale._source, 'reddit-tools', 'slack__search', home), /active|disabled/);
  await rejects('live stale tool execution', staleTool.execute('stale-live-call', {}, undefined, { sessionManager: { getCwd: () => home } }), /active|disabled/);
  assert.equal(liveRegistry.snapshots().find(item => item.name === 'reddit-tools').extensionOwned, false);
  await live.disconnectAll();
  }

  if (process.argv.includes('--disabled')) {
    // Native filtering must preserve disabled names for runtime collision checks.
    for (const data of [
      { mcpServers: { 'reddit-tools': { ...explicit, enabled: false } } },
      { mcpServers: { reddit_tools: { ...explicit, enabled: false } } },
      { mcpServers: {}, disabledServers: ['reddit-tools'] },
      { mcpServers: {}, disabledServers: ['reddit_tools'] },
    ]) {
      const file = join(process.env.PI_CODING_AGENT_DIR, 'mcp.json');
      await writeFile(file, JSON.stringify(data));
      const configs = await loadAllMCPConfigs(home);
      const disabled = new MCPManager(home, undefined, async () => configs);
      await rejects('disabled declaration ' + JSON.stringify(data), extensionMcpRegistry(disabled).register(owner, {}, 'reddit-tools', owned, undefined, () => true), /explicit|collision|disabled|reserved/i);
      assert.equal(await Bun.file(file).text(), JSON.stringify(data));
      await disabled.disconnectAll();
    }
  }
  assert.equal(calls.filter(item => item.method === 'tools/call').length, 0);
  console.log(process.argv.includes('--disabled')
    ? 'PASS: real native config loader reserves disabled literal/normalized declarations and disable lists'
    : 'PASS: real manager late discovery and live reconciliation retire runtime entries; stale handles stay revoked');
} finally { await server.stop(true); }
