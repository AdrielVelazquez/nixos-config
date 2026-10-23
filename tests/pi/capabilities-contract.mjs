import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const f = JSON.parse(await readFile(process.argv[2], 'utf8'));
assert.deepEqual(f.enabled, [true, true], 'Framework must select AST and web profiles');
assert.deepEqual(f.razerEnabled, [false, false], 'Razer must remain unchanged');
assert.deepEqual(f.versions, ['0.4.2', '0.44.0']);
assert.equal(f.uiEnabled, true);
assert.equal(f.razerUiEnabled, false);
assert.equal(f.settings.theme, 'omp-reference');
assert.equal(f.settings.quietStartup, 'header');
assert.ok(f.settings.themes.some(path => path.endsWith('omp-reference.json')));
assert.ok(f.settings.themes.some(path => path.endsWith('omp-dark.json')));
assert.ok(f.uiEntries.ompTheme.endsWith('-pi-omp-theme.ts'));
assert.ok(f.uiEntries.neutralForeground.endsWith('-pi-neutral-foreground.ts'));
assert.ok(f.settings.extensions.indexOf(f.uiEntries.ompTheme) < f.settings.extensions.indexOf(f.uiEntries.neutralForeground));
assert.ok(f.entries.ast.endsWith('-pi-readonly-ast.ts'));
assert.ok(f.entries.web.endsWith('-pi-fetch-only.ts'));
for (const path of Object.values(f.entries)) assert.ok(f.settings.extensions.includes(path), path);
assert.equal(f.settings.defaultThinkingLevel, 'high');
assert.ok(f.required.some(entry => entry.id === 'readonly-ast' && entry.path === f.entries.ast));
assert.ok(f.required.some(entry => entry.id === 'fetch-only' && entry.path === f.entries.web));
assert.ok(f.required.some(entry => entry.id === 'reddit-provider'));
assert.ok(f.required.some(entry => entry.id === 'headroom'));
const ui = f.settings.piOmpTheme;
assert.equal(ui.schemaVersion, 1);
assert.equal(ui.preset, 'omp');
assert.equal(ui.readonlyTools, false);
assert.deepEqual(ui.theme, { autoApply: 'off', terminalBackgroundSync: 'off' });
assert.deepEqual(ui.statusLine.layout, { left: ['pi', 'model_effort', 'path', 'git', 'cost'], right: ['context_pct'], secondary: ['extension_statuses'] });
assert.equal(ui.placement, 'above');
assert.deepEqual(ui.editor, { style: 'boxed', frame: 'rounded' });
assert.equal(ui.startup.mode, 'off');
assert.equal(ui.compatibility.preferExistingEditor, false);
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
