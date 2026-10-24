import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, appendFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { GhostEngine } from '../../dotfiles/pi/extensions/ghost-core.ts';
import { promptsFromSession, commandNames, seedEngine } from '../../dotfiles/pi/extensions/ghost-seed.ts';

const line = (role, content, type = 'message') => JSON.stringify({ type, message: { role, content } });

test('only typed prompts are read from a session log', () => {
  const log = [
    line('user', 'plain prompt'),
    line('user', [{ type: 'text', text: 'block prompt' }, { type: 'image', data: 'x' }]),
    line('assistant', 'assistant words'), line('toolResult', 'tool words'),
    JSON.stringify({ type: 'model_change' }), '{broken',
  ].join('\n');
  assert.deepEqual(promptsFromSession(log).map(prompt => prompt.text), ['plain prompt', 'block prompt']);
});

test('command names come from zsh and bash history without reading arguments', () => {
  const names = commandNames([
    ': 1700000000:0;sudo -E kubectl get pods --namespace secret-ns', '#1700000001',
    'FOO=bar terraform plan | rg needle', 'cd /tmp && /usr/bin/nvim notes.md',
    "git commit -m 'kubecfg; hidden words'", 'docker-compose up', 'ls',
  ].join('\n'));
  for (const expected of ['kubectl', 'terraform', 'nvim', 'git', 'docker', 'compose']) assert.ok(names.has(expected), expected);
  for (const forbidden of ['pods', 'namespace', 'secret', 'needle', 'notes', 'kubecfg', 'hidden', 'words', 'up', 'ls', 'cd']) assert.ok(!names.has(forbidden), forbidden);
});

test('every run of a command is counted', () => {
  const names = commandNames('kubectl a\nkubectl b\n: 1:0;kubectl c | kubectl d\nkubect e');
  assert.equal(names.get('kubectl'), 4);
  assert.equal(names.get('kubect'), 1);
});

test('seeding learns history once, incrementally, and never from agent-written logs', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'ghost-seed-'));
  try {
    const sessions = join(dir, 'sessions'), project = join(sessions, 'proj'), omp = join(dir, 'omp'), history = join(dir, 'history');
    await mkdir(project, { recursive: true }); await mkdir(omp);
    const main = join(project, '2026-10-23T10-00-00-000Z_aaaa.jsonl'), current = join(project, '2026-10-23T11-00-00-000Z_bbbb.jsonl');
    await writeFile(main, [line('user', 'Restart headroomx now.'), line('assistant', 'zebrafish assistant'), line('user', 'Then headroomx again.')].join('\n') + '\n');
    await writeFile(join(project, 'abc_build_0_transcript.jsonl'), line('user', 'subagent prompt quokkaword quokkaword') + '\n');
    await writeFile(current, line('user', 'live session sloganword sloganword') + '\n');
    await writeFile(join(omp, '2026-10-22T09-00-00-000Z_cccc.jsonl'), line('user', 'omp prompt platypusword platypusword') + '\n');
    await writeFile(history, ': 1:0;kubectl get pods\n'.repeat(3) + 'kubect get pods\n' + 'cat file\n'.repeat(5));
    const engine = new GhostEngine(['cat\t0.00001', 'the\t0.05']);
    const options = { piSessions: true, ompSessions: omp, shellHistory: [history] };
    assert.equal(await seedEngine(engine, options, sessions, current, () => false), true);
    const words = engine.snapshot().words;
    assert.equal(words.headroomx, 2);
    assert.equal(words.platypusword, 2);
    assert.ok(words.kubectl >= 2, String(words.kubectl));
    for (const absent of ['zebrafish', 'quokkaword', 'sloganword', 'cat', 'kubect']) assert.equal(words[absent], undefined, absent);
    assert.equal(await seedEngine(engine, options, sessions, current, () => false), false);
    assert.equal(engine.snapshot().words.headroomx, 2);
    await appendFile(main, line('user', 'Third headroomx mention.') + '\n');
    assert.equal(await seedEngine(engine, options, sessions, current, () => false), true);
    assert.equal(engine.snapshot().words.headroomx, 3);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('an aborted seeding run learns nothing and does not throw', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'ghost-seed-'));
  try {
    const sessions = join(dir, 'sessions');
    await mkdir(sessions, { recursive: true });
    await writeFile(join(sessions, '2026-10-23T10-00-00-000Z_aaaa.jsonl'), line('user', 'headroomx headroomx') + '\n');
    const engine = new GhostEngine(['the\t0.05']);
    assert.equal(await seedEngine(engine, { piSessions: true, ompSessions: null, shellHistory: [] }, sessions, undefined, () => true), false);
    assert.equal(engine.snapshot().words.headroomx, undefined);
  } finally { await rm(dir, { recursive: true, force: true }); }
});

test('a message already learned live is not counted again when its session is seeded', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'ghost-seed-'));
  try {
    const sessions = join(dir, 'sessions');
    await mkdir(sessions, { recursive: true });
    const entry = JSON.stringify({ type: 'message', message: { role: 'user', timestamp: 1700000000000, content: 'Restart headroomx now.' } });
    await writeFile(join(sessions, '2026-10-23T10-00-00-000Z_aaaa.jsonl'), entry + '\n');
    const engine = new GhostEngine(['the\t0.05']);
    const { createHash } = await import('node:crypto');
    engine.observe('Restart headroomx now.', createHash('sha256').update(JSON.stringify(['user', 1700000000000, 'Restart headroomx now.'])).digest('hex'));
    await seedEngine(engine, { piSessions: true, ompSessions: null, shellHistory: [] }, sessions, undefined, () => false);
    assert.equal(engine.snapshot().words.headroomx, 1);
  } finally { await rm(dir, { recursive: true, force: true }); }
});
