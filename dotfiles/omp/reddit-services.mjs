import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
import { isProjectId } from './provider-core.mjs';
import { savedProjectChoices, saveProjectSelection } from './reddit-state.mjs';
import { boundedRedditFetch, trustedRedditOrigin } from './reddit-http.mjs';

const PROJECT_RPC = '/api/reddit.llmplatform.controlplane.project.v1alpha.ProjectService/GetOrCreateUserProject';

export async function createRedditServices(options, dependencies = {}) {
  const { provider, agentDir, projectSelection } = options;
  const root = new URL(trustedRedditOrigin(options.controlPlaneOrigin, options.allowTestLoopback === true));
  if (!options.supportPath) throw new Error('Pinned Reddit support modules are unavailable');
  const [quotaModule, uiModule, httpModule] = await Promise.all(['quota.ts', 'reddit-ui.ts', 'http.ts']
    .map(name => import(pathToFileURL(join(options.supportPath, name)).href)));
  const { safeDiagnostic, withDeadline } = httpModule;
  const readers = new Map();
  let closed = false, changing = false, preferenceError;

  function ensureOpen() { if (closed) throw new Error('Reddit services are closed'); }
  function requireMain(ctx) {
    ensureOpen();
    if (ctx.agent?.kind !== 'main') throw new Error('Reddit controls are main-session only');
  }
  function requireProjectMutation(ctx) {
    requireMain(ctx);
    if (projectSelection.locked) throw new Error(`Project is fixed by ${projectSelection.source}; change the explicit override first`);
    if (!ctx.isIdle() || ctx.hasPendingMessages?.()) throw new Error('Wait until the main session is idle before changing project');
    if (ctx.getAsyncJobSnapshot?.()?.running?.length) throw new Error('Wait for background jobs/workers before changing project');
  }

  const boundedFetch = boundedRedditFetch(root.origin, dependencies.fetch ?? fetch);

  async function quotaReader(ctx) {
    requireMain(ctx);
    await provider.providerConfig();
    const id = provider.projectStatus().id;
    if (!isProjectId(id)) throw new Error('No valid project is selected for quota lookup');
    let reader = readers.get(id);
    if (!reader) {
      reader = quotaModule.createQuotaReader({ baseUrl: root.origin, projectId: id, timeoutMs: 5000 }, {
        now: dependencies.now ?? Date.now,
        fetch: (config, init) => quotaModule.fetchQuota(config, { ...init, fetchImpl: boundedFetch }),
      });
      readers.set(id, reader);
    }
    return reader;
  }

  async function previewProject(id, ctx) {
    requireMain(ctx);
    if (projectSelection.locked) throw new Error(`Project is fixed by ${projectSelection.source}`);
    return provider.previewProject(id, { source: id === projectSelection.id ? projectSelection.source : 'directory' });
  }

  async function commitProject(prepared, ctx, selectedModelId) {
    requireProjectMutation(ctx);
    if (changing) throw new Error('Another project change is already in progress');
    const selected = selectedModelId ?? (ctx.model?.provider === 'llmplatform' ? ctx.model.id : undefined);
    if (typeof selected !== 'string' || !prepared.models?.some(model => model.id === selected)) {
      throw new Error('Choose an available model explicitly before changing project');
    }
    changing = true;
    const oldModel = ctx.model;
    let oldConfig, staged = false, committed = false, warning;
    try {
      oldConfig = await provider.providerConfig();
      const candidateConfig = provider.preparedConfiguration(prepared);
      await dependencies.registerProvider(candidateConfig);
      staged = true;
      const model = ctx.modelRegistry.find('llmplatform', selected);
      if (!model || !await dependencies.setModel(model)) throw new Error('Native model binding failed; project was not changed');
      ensureOpen();
      const finalConfig = await provider.commitProject(prepared);
      committed = true;
      try { await dependencies.registerProvider(finalConfig); }
      catch (error) { warning = `Project changed, but native catalog rebinding needs a refresh: ${safeDiagnostic(error)}`; }
      try {
        await saveProjectSelection(agentDir, ctx.cwd, prepared.id === projectSelection.id ? null : prepared.id);
        preferenceError = undefined;
      } catch (error) {
        preferenceError = safeDiagnostic(error);
        warning = `Project changed for this session but its directory choice could not be saved: ${preferenceError}`;
      }
      for (const reader of readers.values()) reader.close();
      readers.clear();
      return { project: provider.projectStatus(), modelId: selected, saved: !preferenceError, warning };
    } catch (error) {
      if (!committed && staged && oldConfig) {
        await Promise.resolve(dependencies.registerProvider(oldConfig)).catch(() => {});
        if (oldModel) await Promise.resolve(dependencies.setModel(oldModel)).catch(() => {});
      }
      throw error;
    } finally { changing = false; }
  }

  return {
    baseUrl: root.origin,
    status: ctx => ({ project: { ...provider.projectStatus(), locked: projectSelection.locked },
      model: ctx.model ? { provider: ctx.model.provider, id: ctx.model.id } : undefined,
      catalog: provider.modelStatus(), transport: { required: true, configured: !!provider.transport()?.proxyURL,
        proxyURL: provider.transport()?.proxyURL }, controlPlaneOrigin: root.origin, preferenceError }),
    modelStatus: () => provider.modelStatus(),
    resolveProject: async ctx => { requireMain(ctx); await provider.providerConfig(); return provider.projectStatus(); },
    async refreshModels(ctx) {
      requireMain(ctx);
      await provider.fetchModels();
      await dependencies.registerProvider(await provider.providerConfig());
    },
    quotaReader,
    async quota(ctx, init = {}) {
      const reading = await (await quotaReader(ctx)).read(init);
      return { reading, text: uiModule.formatQuota(reading) };
    },
    previewProject, commitProject,
    async projectChoices(ctx) {
      requireMain(ctx);
      return { configured: { ...projectSelection }, current: provider.projectStatus(),
        saved: projectSelection.locked ? [] : await savedProjectChoices(agentDir) };
    },
    async previewPersonalProject(ctx) {
      requireMain(ctx);
      if (projectSelection.locked) throw new Error(`Project is fixed by ${projectSelection.source}`);
      const id = await withDeadline(async signal => {
        const response = await boundedFetch(root.origin + PROJECT_RPC, { method: 'POST', signal,
          headers: { Accept: 'application/json', 'Content-Type': 'application/json' }, body: '{}' });
        if (!response.ok) throw new Error(`Reddit personal-project lookup returned HTTP ${response.status}`);
        const result = await response.json();
        if (!isProjectId(result.id)) throw new Error('Reddit returned an invalid personal project');
        return result.id;
      }, 5000, undefined, 'personal project lookup');
      return previewProject(id, ctx);
    },
    close() { closed = true; for (const reader of readers.values()) reader.close(); readers.clear(); },
  };
}
