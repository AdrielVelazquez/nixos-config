import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const fixture = JSON.parse(await readFile(process.argv[2], 'utf8'));
const dir = await mkdtemp(join(tmpdir(), 'pi-workflow-'));
process.env.HOME = dir;
process.env.PI_CODING_AGENT_DIR = join(dir, 'agent');
let session;
try {
  const sdk = await import(pathToFileURL(`${process.env.PI_TEST_PACKAGE_DIR}/dist/index.js`).href);
  const settings = sdk.SettingsManager.inMemory(fixture.settings);
  const loader = new sdk.DefaultResourceLoader({ cwd: dir, agentDir: process.env.PI_CODING_AGENT_DIR,
    settingsManager: settings, noContextFiles: true, noThemes: true });
  await loader.reload();
  assert.deepEqual(loader.getExtensions().errors, []);
  const created = await sdk.createAgentSession({ cwd: dir, agentDir: process.env.PI_CODING_AGENT_DIR,
    settingsManager: settings, resourceLoader: loader, sessionManager: sdk.SessionManager.inMemory() });
  session = created.session;
  await session.bindExtensions({});
  const names = loader.getSkills().skills.map(skill => skill.name);
  assert.equal(new Set(names).size, 23, names.join(', '));
  for (const name of ['brainstorming', 'systematic-debugging', 'test-driven-development',
    'using-superpowers', 'verification-before-completion', 'ce-compound', 'ce-compound-refresh']) assert.ok(names.includes(name), name);
  assert.deepEqual(names.filter(name => name.startsWith('ce-')).sort(), ['ce-compound', 'ce-compound-refresh']);
  assert.equal(names.filter(name => name.startsWith('openspec-')).length, 6);
  assert.ok(!names.includes('vault-v2-migration'));
  for (const skill of loader.getSkills().skills.filter(skill => skill.name.startsWith('ce-'))) {
    await stat(join(skill.baseDir ?? new URL('.', pathToFileURL(skill.filePath)).pathname, 'references/modes.md'));
  }
  assert.deepEqual(loader.getPrompts().prompts.map(prompt => prompt.name).sort(),
    ['opsx-apply', 'opsx-archive', 'opsx-explore', 'opsx-propose', 'opsx-sync', 'opsx-update']);
  const mcp = JSON.parse(await readFile(fixture.mcpFile, 'utf8'));
  assert.equal(mcp.mcpServers.github.headers.Authorization, 'Bearer ${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN}');
  console.log('PASS: real Pi discovers 15 Superpowers + 2 complete CE + 6 OpenSpec skills and six native prompt commands; MCP credential stays a runtime substitution');
} finally { session?.dispose(); await rm(dir, { recursive: true, force: true }); }
