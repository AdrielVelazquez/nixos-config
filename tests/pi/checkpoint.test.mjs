import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import test from 'node:test';
import { createCheckpoints } from '../../dotfiles/pi/extensions/checkpoint.ts';

const git = process.env.CHECKPOINT_TEST_GIT ?? 'git';
const sh = (cwd, ...args) => execFileSync(git, args, { cwd, encoding: 'utf8', env: { ...process.env, GIT_AUTHOR_NAME: 't', GIT_AUTHOR_EMAIL: 't@t', GIT_COMMITTER_NAME: 't', GIT_COMMITTER_EMAIL: 't@t' } });
const write = (root, path, text) => { mkdirSync(join(root, path, '..'), { recursive: true }); writeFileSync(join(root, path), text); };
const read = (root, path) => readFileSync(join(root, path), 'utf8');

/** The extension against a fake Pi: a session branch, a UI that answers from a queue, and real git underneath. */
async function host(overrides = {}, options = {}) {
  const root = mkdtempSync(join(tmpdir(), 'ckpt-wiring-'));
  sh(root, 'init', '-q', '-b', 'main');
  write(root, 'a.txt', 'original a\n');
  write(root, 'sub/b.txt', 'original b\n');
  sh(root, 'add', '-A');
  sh(root, 'commit', '-qm', 'init');
  const handlers = new Map(), commands = new Map();
  // A tree of entries with a leaf, as Pi keeps one; `branch` is always the path from the root to the leaf.
  const tree = new Map();
  let leaf = null, counter = 0;
  const add = (entry) => { entry.parentId = leaf; tree.set(entry.id, entry); leaf = entry.id; return entry; };
  const path = () => { const out = []; for (let id = leaf; id; id = tree.get(id).parentId) out.unshift(tree.get(id)); return out; };
  const branch = new Proxy([], { get: (_target, key) => (key === 'push' ? (entry) => add(entry) : path()[key]?.bind ? path()[key].bind(path()) : path()[key]) });
  const log = { notices: [], confirms: [], selects: [], navigations: [], editor: '' };
  const answers = { confirm: [], select: [] };
  const pi = {
    on: (name, handler) => handlers.set(name, handler),
    registerCommand: (name, spec) => commands.set(name, spec.handler),
    appendEntry: (customType, data) => add({ type: 'custom', id: `e${++counter}`, customType, data }),
  };
  const ctx = {
    cwd: root, hasUI: true, mode: 'tui',
    isIdle: () => overrides.idle ?? true,
    sessionManager: { getBranch: () => path(), getSessionId: () => 'session-1', getLeafId: () => leaf },
    navigateTree: async (id) => {
      log.navigations.push(id);
      const target = tree.get(id);
      // Selecting a user message moves the leaf to its parent, as Pi does so the message can be edited and resent.
      leaf = target.type === 'message' && target.message.role === 'user' ? target.parentId : id;
      return { cancelled: false };
    },
    ui: {
      notify: (message, kind) => log.notices.push([kind ?? 'info', message]),
      confirm: async (title, message) => { log.confirms.push([title, message]); return answers.confirm.length ? answers.confirm.shift() : true; },
      select: async (title, labels) => { log.selects.push([title, labels]); return answers.select.length ? answers.select.shift()(labels) : labels[0]; },
      getEditorText: () => log.editor, setEditorText: (text) => { log.editor = text; },
    },
  };
  createCheckpoints(pi, { git, dataDir: mkdtempSync(join(tmpdir(), 'ckpt-data-')), maxFiles: 1000, maxFileBytes: 1024 * 1024, maxAgeDays: 14, restoreOnTree: 'ask', ...options });
  await handlers.get('session_start')({ reason: 'startup' }, ctx);
  /** One user turn: the prompt event (snapshot), the user message, the agent's changes, an answer. */
  const turn = async (prompt, change) => {
    await handlers.get('before_agent_start')({ messageType: 'user', prompt }, ctx);
    add({ type: 'message', id: `m${++counter}`, message: { role: 'user', content: prompt } });
    change?.(root);
    add({ type: 'message', id: `m${++counter}`, message: { role: 'assistant', content: [] } });
  };
  return { root, handlers, commands, get branch() { return path(); }, add, setLeaf: (id) => { leaf = id; }, ctx, log, answers, turn, run: (name, args = '') => commands.get(name)(args, ctx) };
}

test('each prompt gets a checkpoint entry written before its message; other runs do not', async () => {
  const h = await host();
  await h.turn('first prompt', (root) => write(root, 'a.txt', 'one\n'));
  await h.turn('second prompt');
  const shape = h.branch.map((e) => (e.type === 'custom' ? `checkpoint(${e.data.prompt})` : e.message.role));
  assert.deepEqual(shape, ['checkpoint(first prompt)', 'user', 'assistant', 'checkpoint(second prompt)', 'user', 'assistant']);
  const [first, second] = h.branch.filter((e) => e.type === 'custom');
  assert.match(first.data.commit, /^[0-9a-f]{40}$/);
  assert.notEqual(first.data.tree, second.data.tree, 'the second snapshot saw the first turn\'s edit');
  await h.handlers.get('before_agent_start')({ messageType: 'custom', message: {} }, h.ctx);
  assert.equal(h.branch.filter((e) => e.type === 'custom').length, 2, 'a run started by a custom message is not a prompt');
});

test('/undo restores the files, rewinds the conversation to before the message, and /redo returns both', async () => {
  const h = await host();
  await h.turn('reorganise', (root) => { write(root, 'a.txt', 'agent edit\n'); write(root, 'created.txt', 'new\n'); rmSync(join(root, 'sub/b.txt')); });
  const lastUser = h.branch.filter((e) => e.type === 'message' && e.message.role === 'user').at(-1).id;
  const oldLeaf = h.branch.at(-1).id;
  await h.run('undo');
  const [title, message] = h.log.confirms.at(-1);
  assert.equal(title, 'Undo the last turn?');
  assert.match(message, /↺ revert {2}a\.txt/);
  assert.match(message, /\+ restore sub\/b\.txt/);
  assert.match(message, /− remove {2}created\.txt/);
  assert.equal(read(h.root, 'a.txt'), 'original a\n');
  assert.equal(existsSync(join(h.root, 'created.txt')), false);
  assert.deepEqual(h.log.navigations, [lastUser], 'the tree moves to the user message, so its text returns to the editor');
  assert.match(h.log.notices.at(-1)[1], /Undid the last turn: 3 files restored/);

  h.log.editor = 'reorganise';
  await h.run('redo');
  assert.equal(read(h.root, 'a.txt'), 'agent edit\n');
  assert.equal(read(h.root, 'created.txt'), 'new\n');
  assert.equal(existsSync(join(h.root, 'sub/b.txt')), false);
  assert.deepEqual(h.log.navigations.at(-1), oldLeaf, 'redo returns to the old leaf');
  assert.equal(h.log.editor, '', 'the rewound message is cleared from the editor once it is in the conversation again');
  await h.run('redo');
  assert.equal(h.log.notices.at(-1)[1], 'Nothing to redo');
});

test('declining the dialog changes nothing, and a new prompt clears the redo', async () => {
  const h = await host();
  await h.turn('edit', (root) => write(root, 'a.txt', 'agent edit\n'));
  h.answers.confirm.push(false);
  await h.run('undo');
  assert.equal(read(h.root, 'a.txt'), 'agent edit\n');
  assert.deepEqual(h.log.navigations, []);
  await h.run('undo');
  assert.equal(read(h.root, 'a.txt'), 'original a\n');
  await h.handlers.get('before_agent_start')({ messageType: 'user', prompt: 'something new' }, h.ctx);
  await h.run('redo');
  assert.equal(h.log.notices.at(-1)[1], 'Nothing to redo', 'new work invalidates the redo');
});

test('/checkpoints lists the branch newest first and restores the files only', async () => {
  const h = await host();
  await h.turn('first', (root) => write(root, 'a.txt', 'after first\n'));
  await h.turn('second', (root) => write(root, 'a.txt', 'after second\n'));
  h.answers.select.push(() => undefined);
  await h.run('checkpoints');
  const [, labels] = h.log.selects.at(-1);
  assert.equal(labels.length, 2);
  assert.match(labels[0], /^ 2 · just now · second$/);
  assert.match(labels[1], /^ 1 · just now · first$/);
  h.answers.select.push((all) => all[1]);
  await h.run('checkpoints');
  assert.equal(read(h.root, 'a.txt'), 'original a\n', 'the snapshot before the first prompt');
  assert.deepEqual(h.log.navigations, [], 'the conversation stays put');
  assert.match(h.log.confirms.at(-1)[1], /↺ revert {2}a\.txt/);
  await h.run('redo');
  assert.equal(read(h.root, 'a.txt'), 'after second\n', 'redo puts the files back');
});

test('navigating the tree offers to restore the files to that point, once, and not while /undo moves the tree itself', async () => {
  const h = await host();
  await h.turn('first', (root) => write(root, 'a.txt', 'after first\n'));
  await h.turn('second', (root) => write(root, 'a.txt', 'after second\n'));
  // The user navigates back to just after the first answer: the branch ends there.
  const oldLeafId = h.branch.at(-1).id;
  h.setLeaf(h.branch[2].id);
  await h.handlers.get('session_tree')({ newLeafId: h.branch.at(-1).id, oldLeafId }, h.ctx);
  const [title, message] = h.log.confirms.at(-1);
  assert.equal(title, 'Restore the files to match this point?');
  assert.match(message, /↺ revert {2}a\.txt/);
  assert.equal(read(h.root, 'a.txt'), 'original a\n');
  await h.handlers.get('session_tree')({ newLeafId: h.branch.at(-1).id, oldLeafId: null }, h.ctx);
  assert.equal(h.log.confirms.length, 1, 'the files already match: nothing to ask');

  write(h.root, 'a.txt', 'edited by hand\n');
  h.answers.confirm.push(false);
  await h.handlers.get('session_tree')({ newLeafId: h.branch.at(-1).id, oldLeafId: null }, h.ctx);
  assert.equal(read(h.root, 'a.txt'), 'edited by hand\n', 'declining keeps the working tree as it is');
});

test('restoreOnTree "never" leaves the tree alone', async () => {
  const h = await host({}, { restoreOnTree: 'never' });
  await h.turn('first', (root) => write(root, 'a.txt', 'after first\n'));
  await h.handlers.get('session_tree')({ newLeafId: h.branch.at(-1).id, oldLeafId: null }, h.ctx);
  assert.equal(h.log.confirms.length, 0);
});

test('a missing checkpoint, a busy agent and a project that is too large are explained, not mishandled', async () => {
  const h = await host();
  await h.run('undo');
  assert.equal(h.log.notices.at(-1)[1], 'Nothing to undo: there is no message yet');
  h.add({ type: 'message', id: 'old', message: { role: 'user', content: 'from before checkpoints' } });
  await h.run('undo');
  assert.match(h.log.notices.at(-1)[1], /No checkpoint for your last message/);
  const busy = await host({ idle: false });
  await busy.run('undo');
  assert.match(busy.log.notices.at(-1)[1], /Wait for the run to finish/);

  const big = await host({}, { maxFiles: 1 });
  await big.handlers.get('before_agent_start')({ messageType: 'user', prompt: 'p' }, big.ctx);
  assert.match(big.log.notices.at(-1)[1], /Checkpoints stopped: .*files/);
  assert.equal(big.branch.length, 0, 'no entry is written without a snapshot');
  await big.handlers.get('before_agent_start')({ messageType: 'user', prompt: 'again' }, big.ctx);
  assert.equal(big.log.notices.length, 1, 'one warning, then silence');
  await big.run('undo');
  assert.match(big.log.notices.at(-1)[1], /Checkpoints are off: /);
});

test('a git history that moved since the snapshot is called out in the dialog', async () => {
  const h = await host();
  await h.turn('commit something', (root) => { write(root, 'a.txt', 'committed\n'); sh(root, 'commit', '-qam', 'agent commit'); });
  await h.run('undo');
  assert.match(h.log.confirms.at(-1)[1], /Git moved from [0-9a-f]{7} to [0-9a-f]{7}/);
});

test('a snapshot that was pruned is explained instead of throwing', async () => {
  const h = await host();
  await h.turn('first', (root) => write(root, 'a.txt', 'after first\n'));
  // The session still names the commit, but the private repository no longer has it.
  h.branch.find((e) => e.type === 'custom').data.commit = '0'.repeat(40);
  await h.run('undo');
  assert.match(h.log.notices.at(-1)[1], /Cannot undo: that snapshot is gone \(snapshots are kept 14 days\)/);
  assert.equal(h.log.confirms.length, 0, 'no dialog for something that cannot be done');
  assert.equal(read(h.root, 'a.txt'), 'after first\n');
});
