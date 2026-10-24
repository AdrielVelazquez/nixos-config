const safe = error => String(error?.message ?? error).replace(/Bearer\s+[^\s"'<>]+/gi, 'Bearer [REDACTED]').slice(0, 2000);
const isInteractive = ctx => ctx.hasUI && ctx.mode === 'tui';

/** Native OMP command adapter; controllers own data/auth, this module only presents it. */
export function registerReddit(pi, options) {
  const output = options.writeOutput ?? ((ctx, text, level = 'info') => {
    if (ctx.mode === 'print') console.error(text);
    else if (ctx.hasUI) ctx.ui.notify(text, level);
    else pi.sendMessage({ customType: 'reddit-output', content: text, display: true, details: { level } });
  });
  const service = async (name, ctx) => {
    const value = typeof options[name] === 'function' ? await options[name](ctx) : options[name];
    if (!value) throw new Error(`Reddit ${name} are unavailable; use the managed OMP profile`);
    return value;
  };
  function requireInteractive(ctx) {
    if (!isInteractive(ctx)) throw new Error('This Reddit operation requires an interactive OMP UI');
  }
  async function status(ctx) {
    const state = await (await service('services', ctx)).status(ctx);
    let registry;
    try { registry = await (await service('tools', ctx)).snapshot(ctx); }
    catch (error) { registry = { connection: 'unavailable', error: safe(error) }; }
    const lines = ['Reddit LLM Platform',
      `Project: ${state.project.id ?? 'unresolved'} (${state.project.source}${state.project.locked ? ', locked override' : ''})`,
      `Model: ${state.model ? state.model.provider + '/' + state.model.id : 'not selected'} (${pi.getThinkingLevel?.() ?? 'unknown'} thinking)`,
      `Models: ${state.catalog.count} — ${state.catalog.status}`,
      `Headroom: required; ${state.transport.configured ? 'owned transport configured at ' + state.transport.proxyURL : 'not acquired'}`,
      `Tool Registry: ${registry.connection}${registry.authState === 'stored' ? '; credentials stored (not proof of current access)' : ''}`,
      ...[state.catalog.error, state.project.error, state.preferenceError, registry.error, registry.metadataError].filter(Boolean).map(safe)];
    output(ctx, lines.join('\n'), state.catalog.status === 'unavailable' ? 'warning' : 'info');
  }
  async function quota(ctx) {
    const services = await service('services', ctx);
    let refresh = false;
    for (;;) {
      const value = await services.quota(ctx, { refresh });
      if (!isInteractive(ctx)) { output(ctx, value.text, value.reading.status === 'ready' ? 'info' : 'warning'); return; }
      if (await ctx.ui.select(value.text, ['Refresh', 'Back']) !== 'Refresh') return;
      refresh = true;
    }
  }
  async function project(ctx, requested) {
    requireInteractive(ctx);
    const services = await service('services', ctx);
    const choices = await services.projectChoices(ctx);
    if (choices.configured.locked) {
      output(ctx, `Project is fixed by ${choices.configured.source}: ${choices.configured.id}. Change the explicit override first.`, 'warning'); return;
    }
    let prepared;
    if (requested) prepared = await services.previewProject(requested, ctx);
    else {
      const defaultLabel = `Use configured default (${choices.configured.id})`;
      const saved = new Map(choices.saved.map(id => [`Saved: ${id}`, id]));
      const choice = await ctx.ui.select('Reddit project', [defaultLabel, 'Personal project', 'Enter project ID', ...saved.keys(), 'Back']);
      if (!choice || choice === 'Back') return;
      if (choice === 'Personal project') prepared = await services.previewPersonalProject(ctx);
      else {
        const id = choice === defaultLabel ? choices.configured.id : choice === 'Enter project ID'
          ? (await ctx.ui.input('Project ID'))?.trim() : saved.get(choice);
        if (!id) return;
        prepared = await services.previewProject(id, ctx);
      }
    }
    let model = ctx.model?.provider === 'llmplatform' && prepared.models.some(row => row.id === ctx.model.id) ? ctx.model.id : undefined;
    if (!model) model = await ctx.ui.select('Choose a model for ' + prepared.id, prepared.models.map(row => row.id));
    if (!model || !await ctx.ui.confirm('Switch Reddit project?', `Use ${prepared.id} with ${model} in this directory?`)) return;
    const result = await services.commitProject(prepared, ctx, model);
    output(ctx, result.warning || `Reddit project changed to ${result.project.id} with ${model}.`, result.warning ? 'warning' : 'info');
  }
  async function tools(ctx, parts) {
    const controller = await service('tools', ctx);
    const action = parts[0];
    if (action) {
      requireInteractive(ctx);
      if (action === 'setup') { if (await controller.setup(ctx) !== false) await controller.signIn(ctx); return; }
      if (['login', 'signin'].includes(action)) { await controller.signIn(ctx); return; }
      if (['logout', 'signout'].includes(action)) { await controller.signOut(ctx); return; }
      if (action === 'refresh') { await controller.refresh(ctx); return; }
      if (action === 'details') { await controller.showConnection(ctx); return; }
      if (action === 'provider' && parts.length === 3 && ['on', 'off'].includes(parts[2])) {
        await controller.setProviderEnabled(ctx, parts[1], parts[2] === 'on'); return;
      }
      throw new Error('Usage: /reddit tools [setup|login|logout|refresh|details|provider <id> on|off]');
    }
    for (;;) {
      const snapshot = await controller.snapshot(ctx);
      const heading = [`Reddit tools: ${snapshot.connection}`, snapshot.authState === 'stored' ? 'Credentials stored; service grants may still require sign-in' : '',
        snapshot.error, snapshot.metadataError].filter(Boolean).map(safe).join('\n');
      if (!isInteractive(ctx)) {
        output(ctx, [heading, 'Use the interactive /reddit tools menu for native OMP sign-in.',
          ...snapshot.providers.map(item => `${item.name}: ${item.enabled ? 'On here' : 'Off here'} (${item.tools} known tools)`)].join('\n')); return;
      }
      if (!snapshot.configured) {
        if (await ctx.ui.select(heading, ['Set up Reddit tools', 'Back']) !== 'Set up Reddit tools') return;
        if (await controller.setup(ctx) !== false) await controller.signIn(ctx);
        return;
      }
      const labels = snapshot.providers.map(item => `${item.name}: ${item.enabled ? 'On here' : 'Off here'} (${item.tools} known tools)`);
      const choice = await ctx.ui.select(heading, ['Connection details', 'Sign in / authorize services', 'Sign out', 'Refresh tools', ...labels, 'Back']);
      if (!choice || choice === 'Back') return;
      if (choice === 'Connection details') { await controller.showConnection(ctx); return; }
      if (choice === 'Sign in / authorize services') { await controller.signIn(ctx); return; }
      if (choice === 'Sign out') { await controller.signOut(ctx); return; }
      if (choice === 'Refresh tools') { await controller.refresh(ctx); return; }
      const provider = snapshot.providers[labels.indexOf(choice)];
      if (!provider) continue;
      const toggle = provider.enabled ? 'Turn off here' : 'Turn on here';
      const next = await ctx.ui.select(provider.name, [toggle, ...(provider.authorizeURL ? ['Upstream sign-in link'] : []), 'Back']);
      if (next === toggle) await controller.setProviderEnabled(ctx, provider.id, !provider.enabled);
      else if (next === 'Upstream sign-in link') output(ctx, `Open this advertised sign-in link, then refresh tools: ${provider.authorizeURL}`);
    }
  }
  async function handler(args, ctx) {
    try {
      if (ctx.agent?.kind !== 'main') throw new Error('Reddit controls are main-session only');
      const parts = args.trim().split(/\s+/).filter(Boolean);
      let action = parts.shift()?.toLowerCase();
      if (!action && isInteractive(ctx)) {
        const choice = await ctx.ui.select('Reddit', ['Model status', 'Choose model', 'Project', 'Refresh models', 'Your monthly usage', 'Reddit tools', 'Back']);
        action = { 'Model status': 'status', 'Choose model': 'model', Project: 'project', 'Refresh models': 'refresh', 'Your monthly usage': 'quota', 'Reddit tools': 'tools' }[choice];
        if (!action) return;
      }
      if (!action || action === 'status') await status(ctx);
      else if (action === 'quota') await quota(ctx);
      else if (action === 'project') await project(ctx, parts[0]);
      else if (action === 'model') { requireInteractive(ctx); ctx.ui.setEditorText('/model'); output(ctx, 'Press Enter to open native OMP model selection.'); }
      else if (action === 'refresh') { await (await service('services', ctx)).refreshModels(ctx); output(ctx, 'Reddit model catalog refreshed'); }
      else if (action === 'tools') await tools(ctx, parts);
      else output(ctx, 'Usage: /reddit [status|refresh|quota|tools|project|model]', 'warning');
    } catch (error) { output(ctx, safe(error), 'error'); }
  }
  pi.registerCommand('reddit', { description: 'Reddit models, projects, monthly usage, Tool Registry and sign-in', handler });
  pi.registerCommand('llmplatform', { description: 'Managed LLM Platform status/refresh', handler: (args, ctx) => handler(args.trim() || 'status', ctx) });
}
