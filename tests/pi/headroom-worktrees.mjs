import assert from 'node:assert/strict';
import { execFileSync, spawnSync } from 'node:child_process';
import { mkdtemp, mkdir, readFile, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { test } from 'node:test';
import headroom from '../../dotfiles/pi/extensions/headroom.ts';

const git = (cwd, ...args) => execFileSync('git', ['-C', cwd, ...args], { encoding: 'utf8', env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' } }).trim();
async function repository(base, name) {
  const dir = join(base, name);
  await mkdir(dir);
  git(dir, 'init', '-q', '-b', 'main');
  git(dir, '-c', 'user.name=t', '-c', 'user.email=t@example.invalid', 'commit', '-q', '--allow-empty', '-m', 'seed');
  return await realpath(dir);
}
async function worktree(repo, name) {
  const dir = join(repo, '..', name);
  git(repo, 'worktree', 'add', '-q', '-b', name, dir);
  return await realpath(dir);
}

/** Starts one managed Pi session whose Headroom proxy is bound to `owned`, with Pi's cwd at `cwd`. */
async function launch(base, owned, cwd) {
  const root = await mkdtemp(join(base, 'state-'));
  const started = (await readFile(`/proc/${process.pid}/stat`, 'utf8')).split(')').slice(1).join(')').trim().split(/\s+/)[19];
  await mkdir(join(root, 'leases'));
  await writeFile(join(root, 'state.json'), JSON.stringify({ ready: true, instance: 'fixture', managerPid: process.pid, managerStarted: started, port: 19878, project: owned }));
  await writeFile(join(root, 'config.json'), JSON.stringify({ user: 'fixture-user', adapters: [{ provider: 'llm-platform', upstreamOrigins: ['https://upstream.example'], urlEnv: 'FIXTURE_PROXY', requiredEnv: 'FIXTURE_REQUIRED' }] }));
  Object.assign(process.env, { HEADROOM_PI_STATE_DIR: root, HEADROOM_PI_INSTANCE: 'fixture', HEADROOM_PROXY_URL: 'http://127.0.0.1:19878', HEADROOM_PI_CONFIG: join(root, 'config.json'), FIXTURE_PROXY: 'http://127.0.0.1:19878', FIXTURE_REQUIRED: '1' });
  const handlers = new Map(), notices = [];
  headroom({
    on: (event, fn) => handlers.set(event, fn), events: { on: () => () => {} },
    exec: async (command, args) => {
      const result = spawnSync(command, args, { encoding: 'utf8', env: { ...process.env, GIT_CONFIG_GLOBAL: '/dev/null', GIT_CONFIG_SYSTEM: '/dev/null' } });
      return { code: result.status ?? 1, stdout: result.stdout, stderr: result.stderr };
    },
  });
  const ctx = { cwd, ui: { notify: message => notices.push(message) } };
  const attribution = async () => {
    const event = { headers: { 'x-headroom-base-url': 'https://upstream.example' } };
    await handlers.get('before_provider_headers')(event, ctx);
    return event.headers['x-headroom-cwd'];
  };
  return { handlers, ctx, notices, attribution, start: () => handlers.get('session_start')({}, ctx), input: () => handlers.get('input')({}, ctx) };
}

async function sandbox(run) {
  const base = await realpath(await mkdtemp(join(tmpdir(), 'pi-headroom-worktrees-')));
  const before = { ...process.env };
  try {
    await run(base);
  } finally {
    for (const key of Object.keys(process.env)) if (!(key in before)) delete process.env[key];
    Object.assign(process.env, before);
    await rm(base, { recursive: true, force: true });
  }
}

test('a linked worktree of the managed repository starts and is attributed to the managed project', () => sandbox(async base => {
  const main = await repository(base, 'main');
  const child = await worktree(main, 'pi-worktree-run-0');
  await mkdir(join(child, 'sub'));
  for (const cwd of [child, join(child, 'sub')]) {
    const session = await launch(base, main, cwd);
    await session.start();
    assert.equal(await session.attribution(), main, `${cwd} is attributed to the managed project, not to its own path`);
    assert.deepEqual(await session.input(), undefined, 'input is accepted');
    await session.handlers.get('session_shutdown')({}, session.ctx);
  }
}));

test('a session that itself runs in a worktree accepts the main checkout and its sibling worktrees', () => sandbox(async base => {
  const main = await repository(base, 'main');
  const first = await worktree(main, 'one');
  const second = await worktree(main, 'two');
  for (const cwd of [main, second]) {
    const session = await launch(base, first, cwd);
    await session.start();
    assert.equal(await session.attribution(), first);
    await session.handlers.get('session_shutdown')({}, session.ctx);
  }
}));

test('a different repository is refused, and the session then blocks input with that reason', () => sandbox(async base => {
  const main = await repository(base, 'main');
  const other = await repository(base, 'other');
  const session = await launch(base, main, other);
  await assert.rejects(session.start(), /different repository/);
  assert.deepEqual(await session.input(), { action: 'handled' });
  assert.match(session.notices.at(-1), /different repository/);
}));

test("another repository's own linked worktree is refused", () => sandbox(async base => {
  const main = await repository(base, 'main');
  const other = await repository(base, 'other');
  const foreign = await worktree(other, 'foreign');
  await assert.rejects((await launch(base, main, foreign)).start(), /different repository/);
}));

test('a directory that is not a git checkout is refused', () => sandbox(async base => {
  const main = await repository(base, 'main');
  const plain = join(base, 'plain');
  await mkdir(plain);
  await assert.rejects((await launch(base, main, plain)).start(), /different repository/);
}));

test('when the managed project cannot be inspected, no worktree is accepted on trust', () => sandbox(async base => {
  const main = await repository(base, 'main');
  const child = await worktree(main, 'child');
  const gone = join(base, 'gone');
  await assert.rejects((await launch(base, gone, child)).start(), /different repository/);
}));
