const PROJECT_RPC = '/api/reddit.llmplatform.controlplane.project.v1alpha.ProjectService/GetOrCreateUserProject';
const PROJECT = /^[a-z]([a-z0-9-]{0,61}[a-z0-9])?$/;
export const isProjectId = value => typeof value === 'string' && PROJECT.test(value);
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
  let initialization, key, transport, lastGood, baseUrl, projectId;
  let generation = 0, catalogStatus = 'pending', catalogError;
  let projectSource = options.projectSource ?? (options.projectId !== undefined ? 'configured' : env.LLM_PLATFORM_PROJECT_ID ? 'environment' : 'personal');
  const preparedProjects = new WeakMap();

  async function json(path, init) {
    const attempts = options.retries ?? 1;
    for (let attempt = 0; ; attempt++) {
      const controller = new AbortController();
      let timer;
      try {
        return await Promise.race([
          (async () => {
            const signal = init?.signal ? AbortSignal.any([controller.signal, init.signal]) : controller.signal;
            const response = await fetcher(gateway + path, { ...init, redirect: 'error', signal });
            if (!response.ok) {
              const error = new Error(`LLM Platform HTTP ${response.status}`);
              error.status = response.status;
              error.transient = response.status === 429 || response.status >= 500;
              throw error;
            }
            const reader = response.body?.getReader();
            const chunks = []; let bytes = 0;
            if (reader) while (true) {
              const { done, value } = await reader.read();
              if (done) break;
              bytes += value.byteLength;
              if (bytes > 2 * 1024 * 1024) { void reader.cancel(); throw new Error('LLM Platform response exceeded safe metadata limit'); }
              chunks.push(value);
            }
            const data = new Uint8Array(bytes); let offset = 0;
            for (const chunk of chunks) { data.set(chunk, offset); offset += chunk.byteLength; }
            const text = new TextDecoder().decode(data);
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
    projectId = project;
    baseUrl = url.origin + '/v1';
    return configuration();
  }

  function configuration() {
    const revision = generation;
    return { baseUrl, api: 'openai-completions', apiKey: key, models: lastGood ? structuredClone(lastGood) : [],
      fetchDynamicModels: async () => fetchModels(revision) };
  }

  async function providerConfig() {
    if (!initialization) initialization = initialize().catch(error => {
      initialization = undefined; catalogStatus = 'unavailable'; catalogError = error.message; throw error;
    });
    const config = await initialization;
    // Ordinary native children clear/rebind their source in the shared registry.
    // Seed that rebind from live rows, not the header-stripped disk cache.
    return lastGood ? { ...config, models: structuredClone(lastGood) } : config;
  }

  async function readCatalog(projectKey, signal) {
      const payload = await json('/v1/openai/models', { signal, headers: { Accept: 'application/json',
        Authorization: 'Bearer ' + projectKey, 'X-LLM-Platform-Include-Metadata': 'true' } });
      if (!Array.isArray(payload.data)) throw new Error('LLM Platform catalog is invalid');
      const models = new Map();
      for (const row of payload.data) {
        const model = mapModel(row, gateway, transport);
        if (model) {
          // Native OpenAI transports preserve model Authorization over a changed
          // provider default, keeping in-flight old-project rows paired with auth.
          model.headers.Authorization = 'Bearer ' + projectKey;
          models.set(model.id, model);
        }
      }
      if (models.size === 0) throw new Error('LLM Platform catalog has no supported tool-capable models');
      for (const id of options.requiredModels ?? []) {
        if (!models.has(id)) throw new Error(`Configured role model is unavailable: ${id}; no fallback permitted`);
      }
      return [...models.values()];
  }

  async function fetchModels(revision = generation) {
    await providerConfig();
    if (revision !== generation) throw new Error('Stale project catalog request; project changed');
    const projectKey = key;
    try {
      const models = await readCatalog(projectKey);
      if (revision !== generation) throw new Error('Stale project catalog response; project changed');
      lastGood = models;
      catalogStatus = 'ready'; catalogError = undefined;
      return structuredClone(lastGood);
    } catch (error) {
      if (revision !== generation) throw new Error('Stale project catalog response; project changed');
      catalogStatus = 'unavailable'; catalogError = error.message;
      if (error.transient && lastGood) return structuredClone(lastGood);
      throw error;
    }
  }

  async function previewProject(id, { signal, source = 'directory' } = {}) {
    if (typeof id !== 'string' || !PROJECT.test(id)) throw new Error('Invalid LLM Platform project selection');
    await providerConfig();
    const revision = generation;
    const models = await readCatalog('project/' + id, signal);
    if (revision !== generation) throw new Error('Stale project preview; project changed');
    const prepared = Object.freeze({ id, models: structuredClone(models) });
    preparedProjects.set(prepared, { id, source, models, revision });
    return prepared;
  }

  async function commitProject(prepared) {
    const candidate = preparedProjects.get(prepared);
    if (!candidate) throw new Error('Invalid opaque prepared project');
    if (candidate.revision !== generation) throw new Error('Stale prepared project; already consumed or project changed');
    preparedProjects.delete(prepared);
    generation++;
    projectId = candidate.id; projectSource = candidate.source;
    key = 'project/' + projectId; lastGood = candidate.models;
    catalogStatus = 'ready'; catalogError = undefined;
    initialization = Promise.resolve(configuration());
    return providerConfig();
  }

  function preparedConfiguration(prepared) {
    const candidate = preparedProjects.get(prepared);
    if (!candidate || candidate.revision !== generation) throw new Error('Invalid or stale prepared project');
    return { baseUrl, api: 'openai-completions', apiKey: 'project/' + candidate.id, models: structuredClone(candidate.models),
      fetchDynamicModels: async () => {
        if (!preparedProjects.has(prepared) || candidate.revision !== generation) throw new Error('Stale prepared project catalog');
        return structuredClone(candidate.models);
      },
    };
  }

  return { providerConfig, fetchModels, previewProject, preparedConfiguration, commitProject, transport: () => transport,
    projectStatus: () => ({ id: projectId, source: projectSource, status: catalogStatus, error: catalogError }),
    modelStatus: () => ({ status: catalogStatus, count: lastGood?.length ?? 0, error: catalogError }),
  };
}
