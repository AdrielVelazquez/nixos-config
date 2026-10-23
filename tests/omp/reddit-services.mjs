import assert from 'node:assert/strict';
import { test } from 'node:test';
import { mkdtemp, mkdir, readFile, stat, symlink, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { readProjectSelection, saveProjectSelection } from '../../dotfiles/omp/reddit-state.mjs';
import { createRedditServices } from '../../dotfiles/omp/reddit-services.mjs';
import { createProviderService } from '../../dotfiles/omp/provider-core.mjs';

const supportPath = process.env.OMP_REDDIT_SUPPORT;
const selection = { id: 'opencode-dev', source: 'default', locked: false };
const model = { id: 'fixture/model', x_llm_platform: { capabilities: { api: ['responses'], tools: true,
  reasoning: true, reasoning_efforts: ['none', 'high'] }, limits: { context_window_tokens: 9000, max_output_tokens: 1000 } } };

async function folders() {
  const root = await mkdtemp(join(tmpdir(), 'omp-reddit-services-'));
  const agentDir = join(root, 'agent'), cwd = join(root, 'project'), other = join(root, 'other');
  await Promise.all([agentDir, cwd, other].map(path => mkdir(path, { mode: 0o700 })));
  return { root, agentDir, cwd, other, close: () => rm(root, { recursive: true, force: true }) };
}

test('directory project choices are private, atomic and subordinate to explicit configuration', async () => {
  const f = await folders();
  try {
    assert.deepEqual(await readProjectSelection(f.agentDir, f.cwd, selection), selection);
    await Promise.all([saveProjectSelection(f.agentDir, f.cwd, 'alpha-project'), saveProjectSelection(f.agentDir, f.other, 'beta-project')]);
    assert.equal((await readProjectSelection(f.agentDir, f.cwd, selection)).id, 'alpha-project');
    assert.equal((await readProjectSelection(f.agentDir, f.other, selection)).id, 'beta-project');
    const locked = { id: 'fixed-project', source: 'environment', locked: true };
    assert.deepEqual(await readProjectSelection(f.agentDir, f.cwd, locked), locked);
    assert.equal((await stat(join(f.agentDir, 'reddit/projects.json'))).mode & 0o777, 0o600);
    assert.equal((await stat(join(f.agentDir, 'reddit'))).mode & 0o777, 0o700);
    assert.ok(!(await readFile(join(f.agentDir, 'reddit/projects.json'), 'utf8')).includes('Bearer'));
  } finally { await f.close(); }
});

test('project state refuses symlink files/directories and invalid project IDs', async () => {
  const f = await folders();
  try {
    await symlink(f.other, join(f.agentDir, 'reddit'));
    await assert.rejects(saveProjectSelection(f.agentDir, f.cwd, 'alpha-project'), /symlink|directory|private/i);
    await rm(join(f.agentDir, 'reddit'));
    await saveProjectSelection(f.agentDir, f.cwd, 'alpha-project');
    await rm(join(f.agentDir, 'reddit/projects.json'));
    await symlink(join(f.root, 'outside.json'), join(f.agentDir, 'reddit/projects.json'));
    await assert.rejects(readProjectSelection(f.agentDir, f.cwd, selection), /symlink|state|project/i);
    await assert.rejects(saveProjectSelection(f.agentDir, f.cwd, '../other'), /invalid.*project/i);
  } finally { await f.close(); }
});

async function serviceFixture(projectSelection = selection) {
  const f = await folders(), requests = [];
  const clock = { now: Date.parse('2026-10-23T00:00:00Z') };
  const quotaState = { month: '2026-10', usageMicrodollars: '1234567', hardQuotaPolicy: {
    enforcementMode: 'QUOTA_ENFORCEMENT_MODE_HARD_ERROR', identityType: 'QUOTA_IDENTITY_TYPE_HUMAN',
    scope: 'QUOTA_SCOPE_PROJECT', period: 'QUOTA_PERIOD_MONTHLY', amountMicrodollars: '2000000' } };
  const native = { config: null, model: { provider: 'llmplatform', id: 'fixture/model' }, reject: false };
  const provider = createProviderService({ gatewayOrigin: 'https://models.invalid', projectId: 'alpha-project', projectSource: 'directory', env: {} }, {
    acquire: async () => ({ proxyURL: 'http://127.0.0.1:19999', project: f.cwd }),
    fetch: async () => new Response(JSON.stringify({ data: [model] })),
  });
  await provider.fetchModels();
  native.config = await provider.providerConfig();
  const ctx = { agent: { kind: 'main' }, cwd: f.cwd, isIdle: () => true, getAsyncJobSnapshot: () => ({ running: [], recent: [] }),
    get model() { return native.model; }, modelRegistry: { find: (name, id) => {
      const row = native.config.models.find(item => item.id === id);
      return row && { ...row, provider: name, baseUrl: native.config.baseUrl };
    }, refreshProvider: async () => provider.fetchModels() } };
  const services = await createRedditServices({ provider, agentDir: f.agentDir, controlPlaneOrigin: 'https://control.invalid',
    projectSelection, supportPath }, {
    now: () => clock.now,
    registerProvider: config => { native.config = config; },
    setModel: async value => { if (native.reject) return false; native.model = value; return true; },
    fetch: async (url, options) => {
      requests.push({ url, options });
      const result = { projectId: provider.projectStatus().id, subject: 'QUOTA_STATUS_SUBJECT_CALLER_HUMAN_IDENTITY', ...quotaState };
      for (const key of ['hardQuotaPolicy', 'softQuotaPolicy']) if (result[key]) result[key] = { ...result[key], scopeId: result.projectId };
      return new Response(JSON.stringify(result));
    },
  });
  return { ...f, provider, native, ctx, services, requests, quotaState, clock };
}

test('shared fork quota logic preserves exact amounts, caller subject, cache and no model bearer', async () => {
  const f = await serviceFixture();
  try {
    const quota = await f.services.quota(f.ctx);
    assert.match(quota.text, /Used: \$1\.234567/);
    assert.match(quota.text, /Remaining: \$0\.765433/);
    assert.match(quota.text, /Resets: 2026-11-01 UTC/);
    await f.services.quota(f.ctx);
    assert.equal(f.requests.length, 1);
    assert.equal(f.requests[0].url, 'https://control.invalid/api/reddit.llmplatform.controlplane.project.v1alpha.QuotaService/GetQuotaStatus');
    assert.equal(f.requests[0].options.headers.Authorization, undefined);
    assert.equal(f.requests[0].options.redirect, 'error');
    assert.equal(JSON.parse(f.requests[0].options.body).projectId, 'alpha-project');
  } finally { f.services.close(); await f.close(); }
});

test('project change preflights and binds native model before saving, and refuses non-idle/worker mutations', async () => {
  const f = await serviceFixture();
  try {
    const prepared = await f.services.previewProject('beta-project', f.ctx);
    assert.equal(f.provider.projectStatus().id, 'alpha-project');
    await f.services.commitProject(prepared, f.ctx, 'fixture/model');
    assert.equal(f.provider.projectStatus().id, 'beta-project');
    assert.equal(f.native.config.apiKey, 'project/beta-project');
    assert.equal(f.native.model.headers.Authorization, 'Bearer project/beta-project');
    assert.equal((await readProjectSelection(f.agentDir, f.cwd, selection)).id, 'beta-project');
    const next = await f.services.previewProject('gamma-project', f.ctx);
    await assert.rejects(f.services.commitProject(next, { ...f.ctx, isIdle: () => false }, 'fixture/model'), /idle/i);
    await assert.rejects(f.services.previewProject('gamma-project', { ...f.ctx, agent: { kind: 'sub' } }), /main/i);
    await assert.rejects(f.services.commitProject(next, { ...f.ctx, getAsyncJobSnapshot: () => ({ running: [{ status: 'running' }], recent: [] }) }, 'fixture/model'), /background|job|worker/i);
  } finally { f.services.close(); await f.close(); }
});

test('a rejected native model bind keeps old project/auth and does not save a choice', async () => {
  const f = await serviceFixture();
  try {
    const prepared = await f.services.previewProject('beta-project', f.ctx);
    f.native.reject = true;
    await assert.rejects(f.services.commitProject(prepared, f.ctx, 'fixture/model'), /model|bind/i);
    assert.equal(f.provider.projectStatus().id, 'alpha-project');
    assert.equal(f.native.config.apiKey, 'project/alpha-project');
    assert.equal((await readProjectSelection(f.agentDir, f.cwd, selection)).id, 'opencode-dev');
  } finally { f.services.close(); await f.close(); }
});

test('quota exhaustion, soft/no quotas and UTC rollover use the shared fork behavior', async () => {
  const f = await serviceFixture();
  try {
    f.quotaState.usageMicrodollars = '2000000';
    assert.match((await f.services.quota(f.ctx)).text, /Quota exhausted/);
    f.quotaState.softQuotaPolicy = { ...f.quotaState.hardQuotaPolicy, enforcementMode: 'QUOTA_ENFORCEMENT_MODE_SOFT_ERROR', amountMicrodollars: '3000000' };
    delete f.quotaState.hardQuotaPolicy;
    assert.match((await f.services.quota(f.ctx, { refresh: true })).text, /Soft quota: \$3\.00/);
    delete f.quotaState.softQuotaPolicy;
    assert.match((await f.services.quota(f.ctx, { refresh: true })).text, /No personal quota configured/);
    f.clock.now = Date.parse('2026-11-01T00:00:00Z');
    const stale = await f.services.quota(f.ctx);
    assert.equal(stale.reading.status, 'unavailable');
    assert.equal(stale.reading.data, undefined, 'prior UTC month must not remain current');
    f.quotaState.month = '2026-11';
    assert.match((await f.services.quota(f.ctx, { refresh: true })).text, /Resets: 2026-12-01 UTC/);
  } finally { f.services.close(); await f.close(); }
});

test('explicit project constraints cannot be changed by the Reddit service', async () => {
  const f = await serviceFixture({ id: 'alpha-project', source: 'environment', locked: true });
  try {
    await assert.rejects(f.services.previewProject('beta-project', f.ctx), /fixed|override/i);
    assert.equal(f.provider.projectStatus().id, 'alpha-project');
    assert.equal(f.requests.length, 0);
  } finally { f.services.close(); await f.close(); }
});
