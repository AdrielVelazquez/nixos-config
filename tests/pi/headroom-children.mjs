import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, readdir, rm, stat, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { test } from 'node:test';
import headroom from '../../dotfiles/pi/extensions/headroom.ts';
import { routeCodexThroughHeadroom } from '../../dotfiles/pi/extensions/headroom-codex.ts';
import { createHeadroomChildFactory, registerHeadroomContext } from '../../dotfiles/pi/extensions/headroom-children.ts';

const python = process.env.PI_TEST_PYTHON ?? 'python3';
const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8' }).trim();
async function repository(base, name) {
  const path = join(base, name);
  await mkdir(path);
  git(path, 'init', '-q', '-b', 'main');
  git(path, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'fixture');
  return path;
}
async function stopped(url) {
  for (let attempt = 0; attempt < 100; attempt++) {
    try { await fetch(url + '/health', { signal: AbortSignal.timeout(200) }); } catch { return; }
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.fail('Headroom proxy retained an owner after child disposal');
}
async function sandbox(run) {
  const before = { ...process.env };
  const base = await mkdtemp(join(tmpdir(), 'pi-headroom-children-'));
  const sessions = [], acquired = [];
  let factory;
  try {
    await mkdir(join(base, 'runtime'), { mode: 0o700 });
    const parent = await repository(base, 'parent'), other = await repository(base, 'other');
    const manifest = join(base, 'config.json');
    const config = { version: 1, implementation: resolve('packages/headroom-pi.py'), pythonCommand: python,
      proxyCommand: [python, '-E', resolve('tests/pi/fake-headroom.py')], port: 0, startupTimeout: 3,
      memory: true, codeGraph: false, tuningEnv: {}, adapters: [
        { urlEnv: 'FIXTURE_PROXY', requiredEnv: 'FIXTURE_REQUIRED', upstreamOrigins: ['https://upstream.example'] },
        { provider: 'openai-codex', urlEnv: 'HEADROOM_PI_CODEX_PROXY_URL', requiredEnv: 'HEADROOM_PI_CODEX_PROXY_REQUIRED', upstreamOrigins: ['https://chatgpt.com'] },
      ] };
    await writeFile(manifest, JSON.stringify(config));
    Object.assign(process.env, { XDG_RUNTIME_DIR: join(base, 'runtime'), GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' });
    const owned = JSON.parse(execFileSync(python, ['-E', config.implementation, '--config', manifest, '--acquire', String(process.pid)], { cwd: parent, encoding: 'utf8' }));
    acquired.push(owned);
    Object.assign(process.env, { HEADROOM_PI_CONFIG: manifest, HEADROOM_PI_STATE_DIR: owned.stateDir, HEADROOM_PI_INSTANCE: owned.instance,
      HEADROOM_PI_PROJECT: parent, HEADROOM_PI_MEMORY_DB: owned.memoryDB, HEADROOM_PROXY_URL: owned.proxyURL, FIXTURE_PROXY: owned.proxyURL, FIXTURE_REQUIRED: '1' });
    Object.assign(process.env, { HEADROOM_PI_CODEX_PROXY_URL: owned.proxyURL, HEADROOM_PI_CODEX_PROXY_REQUIRED: '1' });
    registerHeadroomContext('parent-session', process.env);
    const parentEnv = { ...process.env };
    let next = 0;
    const createFactory = () => {
      const runtime = {};
      return { create: async launch => {
        Object.assign(process.env, launch.processEnv);
        if (launch.runtime.fail) throw new Error('intentional native startup failure');
        const handlers = new Map(), env = { ...process.env };
        headroom({ on: (event, fn) => handlers.set(event, fn), events: { on: () => () => {} },
          exec: async (cmd, args) => { const p = spawnSync(cmd, args, { encoding: 'utf8' }); return { code: p.status, stdout: p.stdout, stderr: p.stderr }; } });
        const id = 'child-' + ++next, ctx = { cwd: launch.cwd, sessionManager: { getSessionId: () => id } };
        await handlers.get('session_start')({}, ctx);
        registerHeadroomContext(id, env);
        const session = { id, env, runtime, headers: async () => { const event = { headers: { 'x-headroom-base-url': 'https://upstream.example' } };
          await handlers.get('before_provider_headers')(event, ctx); return event.headers; },
          dispose: async () => handlers.get('session_shutdown')({}, ctx) };
        sessions.push(session);
        return session;
      }, dispose: async () => {} };
    };
    factory = createHeadroomChildFactory(createFactory);
    const launch = (cwd, runtime = {}) => factory.create({ cwd, processEnv: { CHILD_ONLY_FIXTURE: 'fixture' }, runtime: { parentSessionId: 'parent-session', ...runtime } });
    await run({ base, parent, other, owned, parentEnv, launch, config, manifest, factory });
  } finally {
    for (const session of sessions) await session.dispose();
    await factory?.dispose();
    for (const owned of acquired) await rm(owned.leasePath, { force: true });
    for (const url of new Set([...acquired.map(item => item.proxyURL), ...sessions.map(item => item.env.HEADROOM_PROXY_URL)])) await stopped(url);
    // Proxy shutdown precedes the manager's final state write; wait before deleting its registry.
    const registry = join(base, 'runtime', `headroom-pi-${process.getuid()}`);
    for (const name of (await readdir(registry)).filter(name => name !== 'contexts')) {
      const path = join(registry, name, 'state.json');
      for (let attempt = 0; ; attempt++) {
        const state = JSON.parse(await readFile(path, 'utf8'));
        if (!state.ready && state.stopping) break;
        assert.ok(attempt < 200, 'Headroom manager did not finish its final state write');
        await new Promise(done => setTimeout(done, 25));
      }
    }
    for (const key of Object.keys(process.env)) if (!(key in before)) delete process.env[key];
    Object.assign(process.env, before);
    await rm(base, { recursive: true, force: true });
  }
}

async function resourcesStopped(root) {
  for (let attempt = 0; attempt < 150; attempt++) {
    const state = JSON.parse(await readFile(join(root, 'state.json'), 'utf8'));
    if (!state.ready && state.stopping) return;
    await new Promise(resolve => setTimeout(resolve, 50));
  }
  assert.fail('project resources retained after their last owner exited');
}

test('foreign background child owns target resources while sharing inference before native startup', () => sandbox(async ({ other, owned, parentEnv, launch }) => {
  const child = await launch(other);
  assert.equal(child.env.HEADROOM_PROXY_URL, owned.proxyURL);
  assert.notEqual(child.env.HEADROOM_PI_STATE_DIR, owned.stateDir);
  assert.equal(child.env.HEADROOM_PI_PROJECT, other);
  assert.ok(child.env.HEADROOM_PI_MEMORY_DB.startsWith(join(other, '.headroom') + '/'));
  assert.equal((await child.headers())['x-headroom-cwd'], other);
  assert.equal(process.env.HEADROOM_PROXY_URL, parentEnv.HEADROOM_PROXY_URL);
  assert.equal(process.env.CHILD_ONLY_FIXTURE, undefined);
  const leases = await readdir(join(child.env.HEADROOM_PI_STATE_DIR, 'leases'));
  assert.equal(leases.length, 1, 'only the real child session lease remains, not the acquisition lease');
}));

test('same-repository background worktrees isolate project resources and share inference', () => sandbox(async ({ base, parent, owned, launch }) => {
  const worktree = join(base, 'parent-worktree');
  git(parent, 'worktree', 'add', '-q', '-b', 'child', worktree);
  const child = await launch(worktree);
  assert.equal(child.env.HEADROOM_PROXY_URL, owned.proxyURL);
  assert.equal((await child.headers())['x-headroom-cwd'], worktree);
  assert.notEqual(child.env.HEADROOM_PI_MEMORY_DB, owned.memoryDB);
  assert.equal(child.env.HEADROOM_PI_PROJECT, worktree);
}));

test('mixed-repository children keep separate runtimes and routing after another initializes', () => sandbox(async ({ parent, other, parentEnv, launch }) => {
  const [left, right] = await Promise.all([launch(other), launch(parent)]);
  assert.notEqual(left.runtime, right.runtime);
  assert.equal((await left.headers())['x-headroom-cwd'], other);
  assert.equal((await right.headers())['x-headroom-cwd'], parent);
  assert.equal(process.env.HEADROOM_PI_STATE_DIR, parentEnv.HEADROOM_PI_STATE_DIR);
}));

test('nested background runners use the invoking session context, including its linked worktrees', () => sandbox(async ({ base, other, launch }) => {
  const child = await launch(other);
  const worktree = join(base, 'other-worktree');
  git(other, 'worktree', 'add', '-q', '-b', 'nested', worktree);
  // A new runner begins with the original process environment, not the last child's temporary values.
  const nested = await launch(worktree, { parentSessionId: child.id });
  assert.equal(nested.env.HEADROOM_PROXY_URL, child.env.HEADROOM_PROXY_URL);
  assert.equal((await nested.headers())['x-headroom-cwd'], worktree);
  assert.notEqual(nested.env.HEADROOM_PI_MEMORY_DB, child.env.HEADROOM_PI_MEMORY_DB);
}));

test('native startup failure releases acquisition and restores the runner environment', () => sandbox(async ({ base, other, launch, parentEnv }) => {
  await assert.rejects(launch(other, { fail: true }), /intentional native startup failure/);
  assert.equal(process.env.HEADROOM_PI_STATE_DIR, parentEnv.HEADROOM_PI_STATE_DIR);
  assert.equal(process.env.CHILD_ONLY_FIXTURE, undefined);
  const roots = await readdir(join(base, 'runtime', `headroom-pi-${process.getuid()}`));
  for (const root of roots.filter(root => root !== 'contexts')) {
    const state = JSON.parse(await readFile(join(base, 'runtime', `headroom-pi-${process.getuid()}`, root, 'state.json'), 'utf8'));
    if (state.project === other) await resourcesStopped(join(base, 'runtime', `headroom-pi-${process.getuid()}`, root));
  }
}));

test('acquisition failure never enters native child initialization', () => sandbox(async ({ other, launch, config, manifest, parentEnv }) => {
  config.proxyCommand = ['/nonexistent-headroom-fixture'];
  await writeFile(manifest, JSON.stringify(config));
  await assert.rejects(launch(other), /Headroom|nonexistent/);
  assert.equal(process.env.HEADROOM_PROXY_URL, parentEnv.HEADROOM_PROXY_URL);
}));

test('non-Git background target remains refused', () => sandbox(async ({ base, launch }) => {
  const plain = join(base, 'plain'); await mkdir(plain);
  await assert.rejects(launch(plain), /Git repository/);
}));

test('an unchanged managed non-Git directory still accepts its own background children', () => sandbox(async ({ parent, owned, launch }) => {
  await rm(join(parent, '.git'), { recursive: true });
  const child = await launch(parent);
  assert.equal(child.env.HEADROOM_PROXY_URL, owned.proxyURL);
  assert.equal((await child.headers())['x-headroom-cwd'], parent);
}));

test('disposing one child does not terminate a sibling sharing its acquired proxy', () => sandbox(async ({ other, launch }) => {
  const [first, second] = await Promise.all([launch(other), launch(other)]);
  assert.equal(first.env.HEADROOM_PROXY_URL, second.env.HEADROOM_PROXY_URL);
  await first.dispose();
  assert.equal((await fetch(second.env.HEADROOM_PROXY_URL + '/health')).status, 200);
  assert.equal((await second.headers())['x-headroom-cwd'], other);
}));

test('a retained invoking context reacquires its proxy after the previous owner exits', () => sandbox(async ({ other, launch }) => {
  const previous = await launch(other);
  await previous.dispose();
  await resourcesStopped(previous.env.HEADROOM_PI_STATE_DIR);
  assert.equal((await fetch(previous.env.HEADROOM_PROXY_URL + '/health')).status, 200);
  const resumed = await launch(other, { parentSessionId: previous.id });
  assert.equal((await fetch(resumed.env.HEADROOM_PROXY_URL + '/health')).status, 200);
  assert.equal((await resumed.headers())['x-headroom-cwd'], other);
}));

test('runtime contexts are private and never persist unrelated credentials', () => sandbox(async ({ owned }) => {
  process.env.SYNTHETIC_PRIVATE_CREDENTIAL = 'must-not-be-persisted';
  registerHeadroomContext('privacy-fixture', process.env);
  const directory = join(dirname(owned.stateDir), 'contexts');
  assert.equal((await stat(directory)).mode & 0o777, 0o700);
  for (const name of await readdir(directory)) {
    const path = join(directory, name);
    assert.equal((await stat(path)).mode & 0o777, 0o600);
    assert.doesNotMatch(await readFile(path, 'utf8'), /SYNTHETIC_PRIVATE_CREDENTIAL|must-not-be-persisted/);
  }
}));

test('an already-cancelled background launch does not acquire or initialize a child', () => sandbox(async ({ other, factory }) => {
  const cancel = new AbortController(); cancel.abort(new Error('cancelled fixture'));
  await assert.rejects(factory.create({ cwd: other, runtime: { parentSessionId: 'parent-session' }, signal: cancel.signal }), /cancelled fixture/);
}));

test('Codex routing uses the child-owned proxy before native startup and survives nested runners', () => sandbox(async ({ other, owned, launch }) => {
  const child = await launch(other);
  const nested = await launch(other, { parentSessionId: child.id });
  for (const session of [child, nested]) {
    assert.equal(session.env.HEADROOM_PI_CODEX_PROXY_URL, owned.proxyURL);
    assert.equal(session.env.HEADROOM_PI_PROJECT, other);
    assert.equal(session.env.HEADROOM_PI_CODEX_PROXY_URL, session.env.HEADROOM_PROXY_URL);
    assert.equal(session.env.HEADROOM_PI_CODEX_PROXY_REQUIRED, '1');
    const registered = [];
    routeCodexThroughHeadroom({ registerProvider: (id, config) => registered.push([id, config]), on: () => {} },
      { urlEnv: 'HEADROOM_PI_CODEX_PROXY_URL', requiredEnv: 'HEADROOM_PI_CODEX_PROXY_REQUIRED' }, session.env);
    assert.equal(registered[0][0], 'openai-codex');
    assert.equal(registered[0][1].baseUrl, child.env.HEADROOM_PROXY_URL + '/v1');
  }
}));
