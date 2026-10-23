import { realpath } from 'node:fs/promises';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { boundedRedditFetch, trustedRedditOrigin } from './reddit-http.mjs';
import { guardRedditStateDirectory } from './reddit-state.mjs';

const SERVER = 'reddit-tools';
const IDENTITY = 'openid offline_access';
const scopeToken = value => typeof value === 'string' && /^[\x21\x23-\x5b\x5d-\x7e]+$/.test(value);
const eligibleScopes = values => [...new Set(values)].filter(value => !value.startsWith('tool:llmp:')).join(' ') || IDENTITY;
const namespace = name => name.replace(/[^a-zA-Z0-9]/g, '_').replace(/_+/g, '_').toLowerCase();

export async function createRedditTools(pi, options, dependencies = {}) {
  for (const method of ['registerMcpServer', 'unregisterMcpServer', 'getMcpServers']) {
    if (typeof pi[method] !== 'function') throw new Error('This OMP binary needs the Nix-managed Reddit MCP compatibility patch');
  }
  const root = trustedRedditOrigin(options.controlPlaneOrigin, options.allowTestLoopback === true);
  const resource = root + '/api/mcp', issuer = root + '/api/oauth';
  const [stateModule, toolsModule, http] = await Promise.all(['reddit-state.ts', 'reddit-tools.ts', 'http.ts']
    .map(name => import(pathToFileURL(join(options.supportPath, name)).href)));
  const request = boundedRedditFetch(root, dependencies.fetch ?? fetch);
  async function loadPreferences() {
    await guardRedditStateDirectory(options.agentDir);
    return stateModule.loadRedditPreferences(options.agentDir);
  }
  let preferences = await loadPreferences();
  let active = true, owned = false, published = '', latest, metadataError, refreshing, timer, started;
  const canonical = new Map(), abort = new AbortController();
  function ensureActive() { if (!active) throw new Error('Reddit tools extension is closed'); }
  function requireMain(ctx) { ensureActive(); if (ctx.agent?.kind !== 'main') throw new Error('Reddit tools controls are main-session only'); }
  function interactive(ctx) {
    requireMain(ctx);
    if (!ctx.hasUI || ctx.mode !== 'tui') throw new Error('Run Reddit tool controls in an interactive OMP session');
  }
  function providerId(raw) {
    const at = raw.indexOf('__'), id = at > 0 ? raw.slice(0, at) : undefined;
    return stateModule.validProviderId(id) ? id : undefined;
  }
  function permitted(prefs, raw, directory) {
    const id = providerId(raw);
    return prefs.toolsOptIn && !!id && id.toLowerCase() !== 'llmp' && !(prefs.directories[directory]?.disabledProviders ?? []).includes(id);
  }
  const policy = Object.assign(async call => {
    try {
      ensureActive();
      const prefs = await loadPreferences();
      const cwd = await realpath(call.cwd);
      return permitted(prefs, call.toolName, cwd) ? { allow: true } : { allow: false, reason: 'This Reddit provider is disabled here, unknown, or requires first-party authorization' };
    } catch { return { allow: false, reason: 'Reddit tool preferences are unavailable; access remains disabled' }; }
  }, { isVisible: (raw, cwd) => active && !!canonical.get(cwd) && permitted(preferences, raw, canonical.get(cwd)) });

  function cachedScope() {
    const cache = preferences.oauthScopes;
    if (cache?.resource !== resource || cache.issuer !== issuer || !cache.scope.split(' ').every(scopeToken)) return IDENTITY;
    return eligibleScopes(cache.scope.split(' '));
  }
  function conflictError() {
    const error = new Error('An explicit or another-extension Reddit MCP definition already exists; resolve that conflict without replacing its configuration');
    error.code = 'REDDIT_MCP_CONFLICT';
    return error;
  }
  async function conflict() {
    const match = pi.getMcpServers().find(server => namespace(server.name) === namespace(SERVER));
    if (!match) return;
    const sameSource = match.extensionOwned && options.extensionSource && match.source === options.extensionSource;
    if (match.name === SERVER && match.extensionOwned && (owned || sameSource)) return;
    if (owned) { await pi.unregisterMcpServer(SERVER).catch(() => {}); owned = false; published = ''; }
    throw conflictError();
  }
  async function publish(ctx) {
    requireMain(ctx); latest = ctx;
    preferences = await loadPreferences();
    const cwd = await realpath(ctx.cwd);
    canonical.set(ctx.cwd, cwd); canonical.set(cwd, cwd);
    if (!preferences.toolsOptIn) {
      if (owned) await pi.unregisterMcpServer(SERVER);
      owned = false; published = ''; return;
    }
    await conflict();
    const scope = cachedScope();
    const signature = JSON.stringify([cwd, preferences.directories[cwd]?.disabledProviders ?? [], scope]);
    const present = pi.getMcpServers().some(server => server.name === SERVER && server.extensionOwned);
    if (signature !== published || !present) {
      try {
        await pi.registerMcpServer(SERVER, { type: 'http', url: resource, timeout: 10000, instructions: false,
          oauth: { scope, expectedIssuer: issuer, expectedResource: resource } }, policy);
      } catch (error) {
        // Native discovery also reserves names of disabled declarations, which snapshots never list.
        if (!/reserves namespace|namespace collision|owned by another extension/i.test(String(error?.message))) throw error;
        owned = false; published = '';
        throw conflictError();
      }
      owned = true; published = signature;
    }
  }
  async function refreshScopes() {
    ensureActive();
    if (refreshing) return refreshing;
    refreshing = (async () => {
      preferences = await loadPreferences();
      if (!preferences.toolsOptIn) throw new Error('Set up Reddit tools and opt in before metadata discovery');
      const data = await http.withDeadline(async signal => {
        const response = await request(root + '/.well-known/oauth-protected-resource/api/mcp', { headers: { Accept: 'application/json' }, signal });
        if (!response.ok) throw new Error(`Reddit Tool Registry metadata returned HTTP ${response.status}`);
        return response.json();
      }, 5000, abort.signal, 'Tool Registry metadata');
      if (data?.resource?.replace(/\/$/, '') !== resource || !Array.isArray(data.authorization_servers) || !data.authorization_servers.length ||
          !data.authorization_servers.every(value => typeof value === 'string' && value.replace(/\/$/, '') === issuer) ||
          !Array.isArray(data.scopes_supported) || !data.scopes_supported.length || !data.scopes_supported.every(scopeToken)) {
        throw new Error('Tool Registry metadata does not match its trusted resource, issuer and scopes');
      }
      ensureActive();
      preferences = await stateModule.updateRedditPreferences(options.agentDir, prefs => {
        ensureActive();
        if (!prefs.toolsOptIn) throw new Error('Reddit consent was revoked during metadata discovery');
        prefs.oauthScopes = { resource, issuer, scope: eligibleScopes(data.scopes_supported) };
      });
      metadataError = undefined;
    })().catch(error => { if (active) metadataError = http.safeDiagnostic(error); throw error; }).finally(() => { refreshing = undefined; });
    return refreshing;
  }
  function startTimer(ctx) {
    if (timer || !ctx.setInterval) return;
    timer = ctx.setInterval(() => {
      if (active && preferences.toolsOptIn) return refreshScopes().then(() => active && latest ? publish(latest) : undefined).catch(() => {});
    }, 300000);
  }
  function handoff(ctx, command) {
    interactive(ctx);
    ctx.ui.setEditorText(command);
    ctx.ui.notify(`Press Enter to open OMP's native MCP controls (${command}). OMP owns sign-in and credentials.`, 'info');
  }
  async function close() {
    if (!active) return;
    active = false; abort.abort();
    if (timer && latest?.clearTimer) latest.clearTimer(timer);
    timer = undefined;
    if (owned) { owned = false; await pi.unregisterMcpServer(SERVER).catch(() => {}); }
  }
  async function start(ctx) {
    requireMain(ctx);
    if (!started) started = (async () => {
      latest = ctx;
      await publish(ctx);
      if (preferences.toolsOptIn) { await refreshScopes().catch(() => {}); if (active) await publish(ctx); startTimer(ctx); }
    })().catch(error => { started = undefined; throw error; });
    return started;
  }
  pi.on('session_start', async (_event, ctx) => { if (ctx.agent?.kind === 'main') await start(ctx); });
  pi.on('before_agent_start', async (_event, ctx) => { if (ctx.agent?.kind === 'main' && active) await publish(ctx); });
  pi.on('session_shutdown', async (_event, ctx) => { if (ctx.agent?.kind === 'main') await close(); });
  return {
    start,
    async setup(ctx) {
      interactive(ctx); await conflict();
      preferences = await loadPreferences();
      if (!preferences.toolsOptIn && !await ctx.ui.confirm('Connect Reddit tools?', 'Enable the Tool Registry for this OMP installation? Native OMP handles browser sign-in and service authorization.')) return false;
      ensureActive(); await conflict();
      const firstConsent = !preferences.toolsOptIn;
      preferences = await stateModule.updateRedditPreferences(options.agentDir, prefs => { prefs.toolsOptIn = true; });
      try { await refreshScopes(); await publish(ctx); }
      catch (error) {
        // Consent was given to connect; a refused registration must not leave a half-enabled state behind.
        if (firstConsent && error?.code === 'REDDIT_MCP_CONFLICT') {
          preferences = await stateModule.updateRedditPreferences(options.agentDir, prefs => { prefs.toolsOptIn = false; });
        }
        throw error;
      }
      startTimer(ctx); return true;
    },
    async snapshot(ctx) {
      requireMain(ctx); await publish(ctx);
      const server = owned ? pi.getMcpServers().find(item => item.name === SERVER && item.extensionOwned) : undefined;
      const tools = (server?.tools ?? []).map(tool => ({ name: 'mcp__reddit_tools__' + tool.originalName,
        namespace: { name: 'mcp__reddit_tools' }, description: tool.description }));
      const cwd = await realpath(ctx.cwd), disabled = preferences.directories[cwd]?.disabledProviders ?? [];
      return { server: SERVER, url: resource, configured: preferences.toolsOptIn,
        connection: server?.status ?? 'not configured', authState: server?.authState ?? 'none',
        error: server?.error, metadataError,
        providers: toolsModule.registryInventory(tools, resource).filter(item => item.id.toLowerCase() !== 'llmp')
          .map(item => ({ ...item, enabled: !disabled.includes(item.id) })) };
    },
    async setProviderEnabled(ctx, id, enabled) {
      interactive(ctx);
      if (!stateModule.validProviderId(id) || id.toLowerCase() === 'llmp') throw new Error('Invalid or first-party-only Reddit provider');
      const cwd = await realpath(ctx.cwd);
      preferences = await stateModule.updateRedditPreferences(options.agentDir, prefs => {
        const disabled = new Set(prefs.directories[cwd]?.disabledProviders ?? []);
        if (enabled) disabled.delete(id); else disabled.add(id);
        prefs.directories[cwd] = { disabledProviders: [...disabled].sort() };
      });
      await publish(ctx);
    },
    async signIn(ctx) { interactive(ctx); preferences = await loadPreferences(); if (!preferences.toolsOptIn) throw new Error('Set up Reddit tools before signing in'); await refreshScopes(); await publish(ctx); handoff(ctx, '/mcp reauth ' + SERVER); },
    async signOut(ctx) { interactive(ctx); await publish(ctx); handoff(ctx, '/mcp unauth ' + SERVER); },
    async refresh(ctx) { interactive(ctx); await refreshScopes(); await publish(ctx); handoff(ctx, '/mcp reconnect ' + SERVER); },
    async showConnection(ctx) { interactive(ctx); await publish(ctx); handoff(ctx, '/mcp list'); },
    close,
  };
}
