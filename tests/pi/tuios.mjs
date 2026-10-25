// Exercise the generated, unmodified upstream asset without a real daemon.
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import childProcess from 'node:child_process';
import { syncBuiltinESMExports } from 'node:module';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const fixture = JSON.parse(await readFile(process.argv[2], 'utf8'));
const sdk = await import(pathToFileURL(`${process.env.PI_TEST_PACKAGE_DIR}/dist/index.js`).href);
const root = await mkdtemp(join(tmpdir(), 'pi-tuios-'));
const original = childProcess.spawn, reports = [];
process.env.TUIOS_ENV = '1';
try {
  // External report is the boundary under test. Never contact the real daemon.
  childProcess.spawn = (binary, args) => {
    assert.equal(binary, fixture.tuios);
    assert.deepEqual(args.slice(0, 3), ['agent-hook', 'pi', '--integration']);
    assert.match(args[3], /^\d+$/);
    const child = new EventEmitter(); child.stdin = new EventEmitter();
    child.stdin.end = text => { reports.push(JSON.parse(text)); setImmediate(() => child.emit('close', 0)); };
    return child;
  };
  syncBuiltinESMExports();
  const loaded = await sdk.discoverAndLoadExtensions([fixture.entry], root, root);
  assert.deepEqual(loaded.errors, []);
  const extension = loaded.extensions[0];
  let idle = true;
  const ctx = { mode: 'tui', isIdle: () => idle, sessionManager: { getSessionId: () => 'fixture-session', getSessionFile: () => '/synthetic/session.jsonl' } };
  const emit = async (name, event = {}) => { for (const handler of extension.handlers.get(name) ?? []) await handler(event, ctx); };
  await emit('session_start'); idle = false; await emit('agent_start');
  await emit('ui_prompt_start', { kind: 'select', title: 'Choose safely' });
  await emit('ui_prompt_end', { kind: 'select' });
  await emit('session_start', { reason: 'reload' });
  idle = true; await emit('agent_settled');
  await emit('session_shutdown'); // reports are queued; shutdown waits for them
  assert.equal(reports.length, 6);
  assert.ok(reports.every(report => report.session_id === 'fixture-session' && report.transcript_path === '/synthetic/session.jsonl'));
  assert.equal(reports[4].busy, true, 'reload lost working state');
  childProcess.spawn = original;
  syncBuiltinESMExports();
  for (const [index, wanted] of ['idle', 'working', 'needs_input', 'working', 'working', 'done'].entries()) {
    const result = childProcess.spawnSync(fixture.tuios, ['agent-hook', 'pi', '--explain'], {
      input: JSON.stringify(reports[index]), encoding: 'utf8',
      env: { PATH: process.env.PATH, HOME: root, XDG_CONFIG_HOME: root, XDG_RUNTIME_DIR: root },
    });
    const explanation = JSON.parse(result.stderr.trim());
    assert.equal(explanation.report.state, wanted, JSON.stringify(explanation));
    if (wanted === 'needs_input') assert.equal(explanation.report.kind, 'question');
  }
  ctx.mode = 'rpc'; await emit('session_start'); await emit('agent_start'); await emit('agent_settled');
  assert.equal(reports.length, 6, 'headless child reported pane state');
  const failed = childProcess.spawnSync(fixture.tuios, ['agent-hook', 'pi', '--explain'], {
    input: JSON.stringify({ hook_event_name: 'agent_settled', session_id: 'fixture-session', outcome: 'error' }), encoding: 'utf8',
    env: { PATH: process.env.PATH, HOME: root, XDG_CONFIG_HOME: root, XDG_RUNTIME_DIR: root },
  });
  assert.equal(JSON.parse(failed.stderr.trim()).report.state, 'done', 'upstream outcome handling changed; review the companion');
  console.log('PASS: generated exact-package hook, working/question/answer/reload/done payloads, real Tuios parser and no headless child reports; upstream outcome gap confirmed');
} finally { childProcess.spawn = original; syncBuiltinESMExports(); await rm(root, { recursive: true, force: true }); }
