import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, writeFile, symlink, rename, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { createRedditTools } from '../../dotfiles/omp/reddit-tools.mjs';

const supportPath = process.env.OMP_REDDIT_SUPPORT;
const root = 'https://control.invalid', resource = root + '/api/mcp', issuer = root + '/api/oauth';
const nativeTools = [
  { name: 'mcp__reddit_tools_slack_search', originalName: 'slack__search', description: 'Search Slack' },
  { name: 'mcp__reddit_tools_slack_authorize_upstream', originalName: 'slack__authorize_5Fupstream', description: resource + '/upstream-auth/slack/start' },
  { name: 'mcp__reddit_tools_glean_search', originalName: 'glean__search', description: 'Search Glean' },
  { name: 'mcp__reddit_tools_llmp_create_skill', originalName: 'llmp__create_skill', description: 'First-party-only mutation' },
];

async function fixture() {
  const folder = await mkdtemp(join(tmpdir(), 'omp-reddit-tools-'));
  const agentDir = join(folder, 'agent'), cwd = join(folder, 'a'), other = join(folder, 'b');
  await Promise.all([agentDir, cwd, other].map(name => mkdir(name, { mode: 0o700 })));
  const sharedState = await import(pathToFileURL(join(supportPath, 'reddit-state.ts')).href);
  const servers = new Map(), operations = [], requests = [], editors = [], notifications = [], policies = new Map(), handlers = new Map();
  const state = { confirm: false, wrongResource: false, wrongIssuer: false, badScopes: false, closed: false, reserved: false };
  const pi = {
    on(name, handler) { handlers.set(name, [...(handlers.get(name) ?? []), handler]); },
    getMcpServers: () => [...servers.values()].map(item => structuredClone(item)),
    async registerMcpServer(name, config, policy) {
      if (state.reserved) throw new Error('Explicit or disabled MCP configuration reserves namespace: ' + name);
      if (servers.get(name)?.source === 'other-extension') throw new Error('MCP server is owned by another extension');
      operations.push({ action: 'register', name, config }); policies.set(name, policy);
      servers.set(name, { name, source: 'fixture-extension', extensionOwned: true, url: config.url,
        status: 'disconnected', authState: 'none', error: 'Sign-in required', tools: nativeTools });
    },
    async unregisterMcpServer(name) { operations.push({ action: 'unregister', name }); servers.delete(name); },
  };
  const ctx = { agent: { kind: 'main' }, cwd, hasUI: true, mode: 'tui',
    setInterval: () => 1, clearTimer() {},
    ui: { confirm: async () => state.confirm, setEditorText: value => editors.push(value), notify: (...args) => notifications.push(args) } };
  const options = { agentDir, controlPlaneOrigin: root, supportPath, extensionSource: 'fixture-extension' };
  const dependencies = { fetch: async (url, init) => {
    requests.push({ url, init });
    if (state.pause) await state.pause;
    return new Response(JSON.stringify({ resource: state.wrongResource ? 'https://other.invalid/api/mcp' : resource,
      authorization_servers: [state.wrongIssuer ? 'https://other.invalid/api/oauth' : issuer],
      scopes_supported: state.badScopes ? ['openid', 'bad scope with whitespace'] : ['openid', 'offline_access', 'tool:slack:read', 'tool:llmp:skills:read'] }));
  } };
  const controller = await createRedditTools(pi, options, dependencies);
  return { folder, agentDir, cwd, other, sharedState, servers, operations, requests, editors, notifications, policies,
    handlers, state, pi, ctx, options, dependencies, controller,
    async close() { await controller.close(); await rm(folder, { recursive: true, force: true }); } };
}

test('fresh registry is opted out and cancelled setup cannot publish, fetch or authorize', async () => {
  const f = await fixture();
  try {
    assert.equal((await f.controller.snapshot(f.ctx)).configured, false);
    await f.controller.setup(f.ctx);
    assert.equal(f.requests.length, 0); assert.equal(f.operations.length, 0); assert.equal(f.editors.length, 0);
    assert.equal((await f.sharedState.loadRedditPreferences(f.agentDir)).toolsOptIn, false);
    await assert.rejects(f.controller.refresh(f.ctx), /setup|set up|opt.in/i);
    assert.equal(f.requests.length, 0); assert.equal(f.editors.length, 0);
    await assert.rejects(f.controller.setup({ ...f.ctx, hasUI: false, mode: 'print' }), /interactive|UI/i);
  } finally { await f.close(); }
});

test('confirmed setup validates metadata, filters scopes, exposes real inventory and uses native auth handoffs', async () => {
  const f = await fixture();
  try {
    f.state.confirm = true;
    await f.controller.setup(f.ctx);
    const config = f.operations.find(item => item.action === 'register').config;
    assert.equal(config.url, resource);
    assert.equal(config.oauth.scope, 'openid offline_access tool:slack:read');
    assert.equal(config.oauth.expectedIssuer, issuer); assert.equal(config.oauth.expectedResource, resource);
    assert.equal(f.requests[0].url, root + '/.well-known/oauth-protected-resource/api/mcp');
    assert.equal(f.requests[0].init.redirect, 'error');
    const snapshot = await f.controller.snapshot(f.ctx);
    assert.equal(snapshot.configured, true);
    assert.equal(snapshot.connection, 'disconnected');
    assert.deepEqual(snapshot.providers.map(item => item.id), ['glean', 'slack']);
    assert.equal(snapshot.providers.find(item => item.id === 'slack').tools, 1);
    assert.equal(snapshot.providers.find(item => item.id === 'slack').authorizeURL, resource + '/upstream-auth/slack/start');
    await f.controller.signIn(f.ctx);
    assert.equal(f.editors.at(-1), '/mcp reauth reddit-tools');
    await f.controller.signOut(f.ctx);
    assert.equal(f.editors.at(-1), '/mcp unauth reddit-tools');
    await f.controller.refresh(f.ctx);
    assert.equal(f.editors.at(-1), '/mcp reconnect reddit-tools');
    assert.equal((await f.sharedState.loadRedditPreferences(f.agentDir)).toolsOptIn, true);
  } finally { await f.close(); }
});

test('cached discovery is filtered too, and malformed refresh preserves the last validated cache', async () => {
  const f = await fixture();
  try {
    await f.sharedState.updateRedditPreferences(f.agentDir, prefs => {
      prefs.toolsOptIn = true;
      prefs.oauthScopes = { resource, issuer, scope: 'openid offline_access tool:slack:read tool:llmp:skills:write' };
    });
    await f.controller.snapshot(f.ctx);
    assert.ok(f.operations.at(-1).config.oauth.scope.split(' ').every(value => !value.startsWith('tool:llmp:')));
    f.state.confirm = true; await f.controller.signIn(f.ctx);
    const before = (await f.sharedState.loadRedditPreferences(f.agentDir)).oauthScopes;
    for (const bad of ['wrongResource', 'wrongIssuer', 'badScopes']) {
      f.state[bad] = true;
      await assert.rejects(f.controller.signIn(f.ctx), /metadata|resource|issuer|scope/i);
      assert.deepEqual((await f.sharedState.loadRedditPreferences(f.agentDir)).oauthScopes, before);
      f.state[bad] = false;
    }
  } finally { await f.close(); }
});

test('directory choices hide and block raw, guessed and long names using fresh state for every call', async () => {
  const f = await fixture();
  try {
    f.state.confirm = true; await f.controller.setup(f.ctx);
    await f.controller.setProviderEnabled(f.ctx, 'glean', false);
    const policy = f.policies.get('reddit-tools');
    const call = (toolName, cwd = f.cwd) => policy({ serverName: 'reddit-tools', toolName, cwd });
    assert.equal(policy.isVisible('glean__search', f.cwd), false);
    assert.equal((await call('glean__search')).allow, false);
    assert.equal((await call('glean__a_guessed_mutation')).allow, false);
    assert.equal((await call('llmp__create_skill')).allow, false);
    assert.equal((await call('unknown_administrative_call')).allow, false);
    assert.equal((await call('glean__search', f.other)).allow, true);
    const alias = join(f.folder, 'alias'); await symlink(f.cwd, alias);
    assert.equal((await call('glean__search', alias)).allow, false);
    const long = 'p_' + 'x'.repeat(200);
    await f.controller.setProviderEnabled(f.ctx, long, false);
    assert.equal((await call(long + '__search')).allow, false);
    await f.sharedState.updateRedditPreferences(f.agentDir, prefs => { prefs.toolsOptIn = false; });
    assert.equal((await call('slack__search')).allow, false, 'stale handles must see revocation from another session');
    await writeFile(join(f.agentDir, 'reddit/preferences.json'), '{bad-json');
    assert.equal((await call('slack__search')).allow, false, 'bad state is not permission to broaden');
  } finally { await f.close(); }
});

test('explicit and other-extension registry definitions cannot be replaced or authorized', async () => {
  const f = await fixture();
  try {
    f.state.confirm = true;
    f.servers.set('reddit_tools', { name: 'reddit_tools', source: 'native-project', extensionOwned: false, status: 'connected', authState: 'none', tools: [] });
    await assert.rejects(f.controller.setup(f.ctx), /conflict|explicit|already/i);
    assert.equal(f.requests.length, 0); assert.equal(f.operations.length, 0);
    f.servers.clear();
    f.servers.set('reddit-tools', { name: 'reddit-tools', source: 'other-extension', extensionOwned: true, status: 'connected', authState: 'stored', tools: [] });
    await assert.rejects(f.controller.setup(f.ctx), /owned|another|conflict/i);
    assert.equal(f.servers.get('reddit-tools').source, 'other-extension');
    assert.equal(f.editors.length, 0);
  } finally { await f.close(); }
});

test('a disabled native declaration that reserves the name is a conflict, not a raw refusal, and cancelled consent is rolled back', async () => {
  const f = await fixture();
  try {
    f.state.confirm = true; f.state.reserved = true;
    await assert.rejects(f.controller.setup(f.ctx), /resolve that conflict without replacing its configuration/);
    assert.equal((await f.sharedState.loadRedditPreferences(f.agentDir)).toolsOptIn, false, 'consent persisted for a registration that was refused');
    assert.equal(f.editors.length, 0); assert.equal(f.operations.length, 0);
  } finally { await f.close(); }
});

test('a reservation discovered at startup reports the conflict but keeps earlier consent', async () => {
  const f = await fixture();
  try {
    await f.sharedState.updateRedditPreferences(f.agentDir, prefs => { prefs.toolsOptIn = true; });
    f.state.reserved = true;
    await assert.rejects(f.controller.start(f.ctx), /resolve that conflict without replacing its configuration/);
    assert.equal((await f.sharedState.loadRedditPreferences(f.agentDir)).toolsOptIn, true);
    assert.equal(f.operations.length, 0, 'a refused reservation still published a server');
    f.state.reserved = false;
    await f.controller.start(f.ctx);
    assert.equal(f.servers.get('reddit-tools')?.extensionOwned, true, 'a resolved conflict did not recover on the next start');
    const registrations = f.operations.filter(item => item.action === 'register');
    assert.ok(!registrations.at(-1).config.oauth.scope.includes('tool:llmp:'));
  } finally { await f.close(); }
});

test('concurrent controllers preserve both directory choices and keep shared consent distinct', async () => {
  const f = await fixture();
  let second;
  try {
    f.state.confirm = true; await f.controller.setup(f.ctx);
    second = await createRedditTools(f.pi, f.options, f.dependencies);
    await Promise.all([f.controller.setProviderEnabled(f.ctx, 'glean', false), second.setProviderEnabled(f.ctx, 'slack', false)]);
    const prefs = await f.sharedState.loadRedditPreferences(f.agentDir);
    assert.deepEqual(prefs.directories[f.cwd].disabledProviders, ['glean', 'slack']);
    assert.equal(prefs.toolsOptIn, true);
    const policy = f.policies.get('reddit-tools');
    for (const raw of ['glean__search', 'slack__search']) assert.equal((await policy({ serverName: 'reddit-tools', toolName: raw, cwd: f.cwd })).allow, false);
  } finally { await second?.close(); await f.close(); }
});

test('closing during metadata discovery cannot write a late cache or resurrect a server', async () => {
  const f = await fixture();
  let release;
  try {
    f.state.confirm = true;
    f.state.pause = new Promise(resolve => { release = resolve; });
    const pending = f.controller.setup(f.ctx);
    pending.catch(() => {});
    const deadline = Date.now() + 2000;
    while (f.requests.length === 0 && Date.now() < deadline) await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.requests.length, 1);
    await f.controller.close();
    release();
    await assert.rejects(pending, /closed|aborted|unloaded/i);
    assert.equal(f.operations.filter(item => item.action === 'register').length, 0);
    assert.equal((await f.sharedState.loadRedditPreferences(f.agentDir)).oauthScopes, undefined);
  } finally { release?.(); await f.close(); }
});

test('consent revoked during discovery prevents a late cache write or publication', async () => {
  const f = await fixture();
  let release;
  try {
    f.state.confirm = true;
    f.state.pause = new Promise(resolve => { release = resolve; });
    const pending = f.controller.setup(f.ctx);
    pending.catch(() => {});
    const deadline = Date.now() + 2000;
    while (f.requests.length === 0 && Date.now() < deadline) await new Promise(resolve => setImmediate(resolve));
    assert.equal(f.requests.length, 1);
    await f.sharedState.updateRedditPreferences(f.agentDir, prefs => { prefs.toolsOptIn = false; });
    release();
    await assert.rejects(pending, /opt.in|consent|set up/i);
    const prefs = await f.sharedState.loadRedditPreferences(f.agentDir);
    assert.equal(prefs.toolsOptIn, false);
    assert.equal(prefs.oauthScopes, undefined);
    assert.equal(f.operations.filter(item => item.action === 'register').length, 0);
  } finally { release?.(); await f.close(); }
});

test('restored registry startup is explicit and idempotent across lazy initialization and native session hooks', async () => {
  const f = await fixture();
  try {
    await f.sharedState.updateRedditPreferences(f.agentDir, prefs => { prefs.toolsOptIn = true; });
    await Promise.all([f.controller.start(f.ctx), f.controller.start(f.ctx)]);
    for (const hook of f.handlers.get('session_start') ?? []) await hook({}, f.ctx);
    assert.equal(f.requests.length, 1, 'startup metadata was fetched more than once');
    assert.equal((await f.controller.snapshot(f.ctx)).configured, true);
  } finally { await f.close(); }
});

test('a symlinked registry state directory cannot import foreign consent at startup', async () => {
  const f = await fixture();
  try {
    const foreign = join(f.folder, 'foreign-state'); await mkdir(foreign);
    await writeFile(join(foreign, 'preferences.json'), JSON.stringify({ version: 1, toolsOptIn: true, directories: {} }));
    await symlink(foreign, join(f.agentDir, 'reddit'));
    await assert.rejects(createRedditTools(f.pi, f.options, f.dependencies), /directory|symlink|private|state/i);
    await assert.rejects(f.controller.start(f.ctx), /directory|symlink|private|state/i);
    assert.equal(f.requests.length, 0); assert.equal(f.operations.length, 0);
  } finally { await f.close(); }
});

test('stale registry call policy rejects a newly symlinked state directory', async () => {
  const f = await fixture();
  try {
    f.state.confirm = true; await f.controller.setup(f.ctx);
    const policy = f.policies.get('reddit-tools');
    const foreign = join(f.folder, 'foreign-state'); await mkdir(foreign);
    await writeFile(join(foreign, 'preferences.json'), JSON.stringify({ version: 1, toolsOptIn: true, directories: {} }));
    await rename(join(f.agentDir, 'reddit'), join(f.agentDir, 'original-reddit'));
    await symlink(foreign, join(f.agentDir, 'reddit'));
    assert.equal((await policy({ serverName: 'reddit-tools', toolName: 'slack__search', cwd: f.cwd })).allow, false);
  } finally { await f.close(); }
});
