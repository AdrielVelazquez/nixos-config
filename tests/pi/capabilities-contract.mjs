import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const f = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.deepEqual(f.enabled, [true, true, true], 'Framework must select the audited profiles');
assert.deepEqual(f.razerEnabled, [false, false, false], 'Razer must remain unchanged');
assert.deepEqual(f.versions, ['0.32.0', '0.4.2', '0.44.0']);
assert.ok(f.entries.editor.endsWith('-pi-visuals.ts'), 'managed full visual layer must be selected');
assert.equal(f.settings.theme, 'managed-opencode');
assert.equal(f.settings.quietStartup, 'header');
assert.ok(f.settings.themes.some(path => path.endsWith('managed-opencode.json')));
assert.ok(f.entries.ast.endsWith('-pi-readonly-ast.ts'));
assert.ok(f.entries.web.endsWith('-pi-fetch-only.ts'));
for (const path of Object.values(f.entries)) assert.ok(f.settings.extensions.includes(path), path);
assert.equal(f.settings.defaultProvider, 'llm-platform');
assert.equal(f.settings.defaultModel, 'gpt-6.1-sol');
assert.equal(f.settings.defaultThinkingLevel, 'high');
assert.ok(f.required.some(entry => entry.id === 'readonly-ast' && entry.path === f.entries.ast));
assert.ok(f.required.some(entry => entry.id === 'fetch-only' && entry.path === f.entries.web));
assert.ok(f.required.some(entry => entry.id === 'reddit-provider'));
assert.ok(f.required.some(entry => entry.id === 'headroom'));
const ui = JSON.parse(await readFile(f.files['zentui.json'], 'utf8'));
assert.equal(ui.components.editor.style, 'opencode');
assert.equal(ui.components.editor.styles.opencode.completionMenu, 'native');
assert.equal(ui.components.footer.style, 'native');
assert.equal(ui.projectRefreshIntervalMs, 0);
assert.equal(ui.components.userMessages.enabled, true);
assert.equal(ui.components.userMessages.style, 'framed-copy-friendly');
assert.equal(ui.components.toolDisplay.enabled, true);
assert.equal(ui.components.toolDisplay.style, 'balanced');
assert.deepEqual(ui.components.toolDisplay.customToolOverrides, {});
assert.deepEqual(ui.components.toolDisplay.builtinRendererOverrides, {});
for (const name of ['selectorBorders', 'thinkingSteps', 'workingLine']) assert.equal(ui.components[name].enabled, false, name);
assert.equal(ui.components.extensionStatuses.defaultVisibility, 'show');
const web = JSON.parse(await readFile(f.files['web-search.json'], 'utf8'));
assert.equal(web.webSearch.enabled, false);
assert.deepEqual(web.fetch.allowedModes, ['readable', 'raw']);
assert.deepEqual(web.fetchRouting.providers, ['http']);
assert.equal(web.fetchContent.redirects, 'same-origin');
for (const key of ['pdf', 'video', 'image', 'youtube', 'githubClone', 'githubPrIssue']) assert.equal(web[key].enabled, false, key);
assert.equal(web.allowBrowserCookies, false);
assert.deepEqual(web.authFetch, {});
assert.deepEqual(web.ssrf, { allowRanges: [], trustEnvProxy: false });
assert.equal(web.toolActivation, 'eager');
for (const value of Object.values(web.commands)) assert.equal(value.enabled, false);
for (const [name, role] of Object.entries(f.roles)) {
  assert.ok(!role.includes('ast_grep_rewrite'), name);
  if (['scout', 'explore'].includes(name)) {
    assert.ok(role.includes('ast_grep_run'), name);
    const tools = role.match(/^tools: (.*)$/m)[1].split(', ');
    for (const denied of ['bash', 'write', 'edit', 'subagent']) assert.ok(!tools.includes(denied), `${name}: ${denied}`);
    assert.equal(tools.includes('fetch_content'), name === 'scout');
  }
}
assert.ok(!JSON.stringify(f.settings).match(/pi-lens|permission-system|pi-lsp-extension|model-aware-compaction|pi-powerline|pi-arnative/));
console.log('PASS: exact audited profiles, immutable policy, existing provider/Headroom and Framework/Razer role isolation');
