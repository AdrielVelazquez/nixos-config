const PROJECT_RPC = '/api/reddit.llmplatform.controlplane.project.v1alpha.ProjectService/GetOrCreateUserProject';
const PROJECT = /^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$/;
const EFFORTS = ['minimal', 'low', 'medium', 'high', 'xhigh', 'max'];
const KNOWN = {
  'gpt-6.1-sol': { api: 'openai-responses', window: 1050000, output: 128000 },
  'gpt-6-luna': { api: 'openai-responses', window: 1050000, output: 128000 },
  'claude-sonnet-5-5': { api: 'openai-completions', window: 1000000, output: 128000 },
};
const positive = value => Number.isSafeInteger(value) && value > 0 ? value : undefined;
const price = value => typeof value === 'number' && Number.isFinite(value) && value >= 0 ? value : 0;

export function mapModel(row, origin, transport) {
  if (typeof row?.id !== 'string' || !row.id.trim()) return undefined;
  const id = row.id.trim(), fallback = KNOWN[id], meta = row.x_llm_platform ?? {}, caps = meta.capabilities ?? {};
  if (/(^|[-_])(tts|transcribe|embedding|embed)([-_]|$)|^veo-|video/i.test(id) || caps.tools === false || (!fallback && caps.tools !== true)) return undefined;
  const apis = Array.isArray(caps.api) ? caps.api : undefined;
  const api = apis ? (apis.includes('responses') ? 'openai-responses' : apis.includes('chat_completions') ? 'openai-completions' : undefined) : row.x_llm_platform ? undefined : fallback?.api;
  if (!api) return undefined;
  const limits = meta.limits ?? {};
  let contextWindow = positive(limits.context_window_tokens) ?? fallback?.window;
  const maxTokens = positive(limits.max_output_tokens) ?? fallback?.output;
  if (!contextWindow || !maxTokens) return undefined;
  if (positive(limits.max_input_tokens)) contextWindow = Math.min(contextWindow, limits.max_input_tokens);
  const advertised = Array.isArray(caps.reasoning_efforts) ? caps.reasoning_efforts : fallback ? ['none', 'low', 'medium', 'high', 'xhigh'] : [];
  const efforts = EFFORTS.filter(level => advertised.includes(level));
  const reasoning = (row.x_llm_platform ? caps.reasoning === true : !!fallback) && efforts.length > 0;
  const canDisable = advertised.includes('none') || advertised.includes('off');
  const p = meta.pricing ?? {};
  const inputs = Array.isArray(caps.modalities?.input) ? caps.modalities.input.filter(kind => ['text', 'image'].includes(kind)) : ['text'];
  return { id, name: row.name ?? id, api, reasoning, input: inputs.length ? inputs : ['text'],
    ...(reasoning ? { thinking: { mode: 'effort', efforts, ...(!canDisable ? { requiresEffort: true } : {}) } } : {}),
    contextWindow, maxTokens,
    cost: { input: price(p.input), output: price(p.output), cacheRead: price(p.cache_read_input ?? p.cached_input), cacheWrite: price(p.cache_write_5m_input) },
    headers: { 'x-headroom-base-url': origin,
      'x-headroom-original-path': '/v1/openai/' + (api === 'openai-responses' ? 'responses' : 'chat/completions'),
      'x-headroom-cwd': transport.project, 'x-client': 'omp' },
    compat: { supportsStore: false, supportsLongPromptCacheRetention: false, supportsPromptCacheBreakpoints: false,
      statefulResponses: false, thinkingFormat: 'openai', trustExplicitThinkingOnly: true,
      supportsReasoningEffort: reasoning, reasoningDisableMode: canDisable ? 'none-effort' : 'lowest-effort',
      supportsDeveloperRole: true, maxTokensField: 'max_completion_tokens' },
  };
}

/** OMP-native provider contract. No modern Pi imports, auth files, or direct inference. */
export function createProviderService(options, dependencies) {
  const origin = new URL(options.gatewayOrigin);
  const testLoopback = options.allowTestLoopback === true && origin.protocol === 'http:' && ['127.0.0.1', '[::1]'].includes(origin.hostname);
  if ((!testLoopback && origin.protocol !== 'https:') || origin.username || origin.password || origin.search || origin.hash || origin.pathname !== '/') throw new Error('Invalid trusted gateway origin');
  const gateway = origin.origin, env = options.env ?? process.env;
  const fetcher = dependencies.fetch ?? fetch;
  let initialization, key, transport, lastGood;

  async function json(path, init) {
    const attempts = options.retries ?? 1;
    for (let attempt = 0; ; attempt++) {
      const controller = new AbortController();
      let timer;
      try {
        return await Promise.race([
          (async () => {
            const response = await fetcher(gateway + path, { ...init, signal: controller.signal });
            if (!response.ok) {
              const error = new Error(`LLM Platform HTTP ${response.status}`);
              error.transient = response.status === 429 || response.status >= 500;
              throw error;
            }
            const text = await response.text();
            if (text.length > 2 * 1024 * 1024) throw new Error('LLM Platform response exceeded safe metadata limit');
            try { return JSON.parse(text); } catch { throw new Error('LLM Platform returned invalid metadata'); }
          })(),
          new Promise((_, reject) => { timer = setTimeout(() => {
            controller.abort(); const error = new Error('LLM Platform metadata request timed out'); error.transient = true; reject(error);
          }, options.timeoutMs ?? 10000); }),
        ]);
      } catch (error) {
        if (error instanceof TypeError) error.transient = true;
        if (!error.transient || attempt >= attempts) throw error;
      } finally { clearTimeout(timer); controller.abort(); }
    }
  }

  async function initialize() {
    const explicit = options.projectId ?? env.LLM_PLATFORM_PROJECT_ID;
    if (explicit !== undefined && !PROJECT.test(explicit)) throw new Error('Invalid LLM Platform project override');
    transport = await dependencies.acquire();
    const url = new URL(transport.proxyURL);
    if (url.protocol !== 'http:' || url.hostname !== '127.0.0.1' || url.username || url.password || url.pathname !== '/' || !url.port) throw new Error('Owned Headroom transport is invalid');
    const project = explicit ?? (await json(PROJECT_RPC, { method: 'POST', headers: { 'Content-Type': 'application/json', Accept: 'application/json' }, body: '{}' })).id;
    if (!PROJECT.test(project ?? '')) throw new Error('LLM Platform returned invalid project identity');
    key = 'project/' + project;
    return { baseUrl: url.origin + '/v1', api: 'openai-completions', apiKey: key, models: [],
      fetchDynamicModels: async () => fetchModels() };
  }

  async function providerConfig() {
    if (!initialization) initialization = initialize().catch(error => { initialization = undefined; throw error; });
    const config = await initialization;
    // Ordinary native children clear/rebind their source in the shared registry.
    // Seed that rebind from live rows, not the header-stripped disk cache.
    return lastGood ? { ...config, models: lastGood } : config;
  }

  async function fetchModels() {
    await providerConfig();
    try {
      const payload = await json('/v1/openai/models', { headers: { Accept: 'application/json',
        Authorization: 'Bearer ' + key, 'X-LLM-Platform-Include-Metadata': 'true' } });
      if (!Array.isArray(payload.data)) throw new Error('LLM Platform catalog is invalid');
      const models = new Map();
      for (const row of payload.data) { const model = mapModel(row, gateway, transport); if (model) models.set(model.id, model); }
      if (models.size === 0) throw new Error('LLM Platform catalog has no supported tool-capable models');
      for (const id of options.requiredModels ?? []) {
        if (!models.has(id)) throw new Error(`Configured role model is unavailable: ${id}; no fallback permitted`);
      }
      lastGood = [...models.values()];
      return lastGood;
    } catch (error) {
      if (error.transient && lastGood) return lastGood;
      throw error;
    }
  }
  return { providerConfig, fetchModels, transport: () => transport };
}
