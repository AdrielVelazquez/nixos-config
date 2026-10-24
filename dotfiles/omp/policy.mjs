const READ_MCP = new Set([
  'mcp__headroom_stats', 'mcp__headroom_memory_memory_search',
  'mcp__github_search_code', 'mcp__github_get_file_contents', 'mcp__github_search_repositories',
  'mcp__serena_read_file', 'mcp__serena_list_dir', 'mcp__serena_find_file',
  'mcp__serena_search_for_pattern', 'mcp__serena_find_symbol',
  'mcp__serena_get_symbols_overview', 'mcp__serena_find_referencing_symbols',
]);
const deny = reason => ({ block: true, reason });

// Native read/search accept opaque MCP URIs, mistyped URLs and delimited paths.
// Do not use WHATWG URL classification: it misses those and hides ?q after #.
function safePath(value, externalRead = false, nativeRead = false) {
  if (typeof value !== 'string' || /[;\r\n]/.test(value)) return false;
  const path = value.trim();
  const query = path.indexOf('?');
  if (query !== -1 && [...new URLSearchParams(path.slice(query + 1)).keys()].some(key => key.toLowerCase() === 'q')) return false;
  const canonical = /^(?:https?:\/\/|file:\/\/|skill:\/\/)/i.exec(path)?.[0];
  if (nativeRead && canonical && !/[\s,]/.test(path)) {
    if (/^https?:/i.test(canonical) && !externalRead) return false;
    // A second scheme can be recovered by native path normalization/fan-out.
    return !/[a-z][a-z0-9+.-]*:\/?\//i.test(path.slice(canonical.length));
  }
  return !/(?:^|[\s,])[a-z][a-z0-9+.-]*:|[a-z][a-z0-9+.-]*:\/|(?:^|[\s,])www\./i.test(path);
}

export function toolDecision(event, ctx) {
  if (ctx.agent?.kind !== 'sub' || !['scout', 'explore'].includes(ctx.agent.name)) return undefined;
  const name = ctx.agent.name, tool = event.toolName;
  if (READ_MCP.has(tool)) return undefined;
  if (['find', 'grep', 'glob'].includes(tool)) {
    const path = event.input?.path;
    const paths = path === undefined ? ['.'] : Array.isArray(path) ? path : [path];
    if (paths.length && paths.every(value => safePath(value))) return undefined;
    return deny('Read-only worker searches accept local paths only');
  }
  if (tool === 'web_search' && name === 'scout') return undefined;
  if (tool === 'read') {
    const path = event.input?.path;
    if (safePath(path, name === 'scout', true)) return undefined;
  }
  return deny(`${name} may only use its explicit read-only operations; ${tool} is unavailable`);
}

export async function spawnDecision(routes, event, ctx) {
  const selected = routes[event.agent];
  if (!selected) return deny('No managed model route for this worker');
  if (event.patterns?.some(pattern => pattern !== selected)) return deny('Worker model override would change the managed route');
  try {
    const selector = selected.replace(/:(off|minimal|low|medium|high|xhigh|max)$/, '');
    const slash = selector.indexOf('/');
    const model = ctx.modelRegistry.find(selector.slice(0, slash), selector.slice(slash + 1));
    if (!model || model.provider !== 'llmplatform') return deny('Configured worker model is unavailable; no fallback permitted');
    const key = await ctx.modelRegistry.getApiKey(model);
    if (typeof key !== 'string' || !key.startsWith('project/')) return deny('Configured worker project authentication is unavailable; no parent fallback permitted');
    return { model: selected };
  } catch { return deny('Worker model/authentication preflight failed; no fallback permitted'); }
}
