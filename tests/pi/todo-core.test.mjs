import test from 'node:test';
import assert from 'node:assert/strict';
import { applyTodo, emptyState, formatTodos, panelLines, progress, stateFromEntries } from '../../dotfiles/pi/extensions/todo-core.ts';

const apply = (state, input) => applyTodo(state, input);
const statuses = state => state.todos.map(todo => `${todo.id}:${todo.status}`).join(' ');
const three = () => apply(emptyState(), { op: 'init', items: ['write test', 'implement', 'document'] });

test('init numbers the tasks from 1 and starts the first one', () => {
  assert.equal(statuses(three()), '1:in_progress 2:pending 3:pending');
  const replaced = apply(three(), { op: 'init', items: ['only'] });
  assert.equal(statuses(replaced), '1:in_progress');
  assert.equal(replaced.nextId, 2);
});

test('finishing the current task starts the next pending one, and the last one leaves nothing in progress', () => {
  let state = apply(three(), { op: 'done', id: 1 });
  assert.equal(statuses(state), '1:done 2:in_progress 3:pending');
  state = apply(apply(state, { op: 'done', id: 2 }), { op: 'done', id: 3 });
  assert.equal(statuses(state), '1:done 2:done 3:done');
  assert.deepEqual(progress(state), { done: 3, total: 3, current: undefined });
});

test('start moves the single in-progress marker and can reopen a finished task', () => {
  let state = apply(three(), { op: 'start', id: 3 });
  assert.equal(statuses(state), '1:pending 2:pending 3:in_progress');
  state = apply(apply(state, { op: 'done', id: 3 }), { op: 'start', id: 3 });
  assert.equal(statuses(state), '1:pending 2:pending 3:in_progress');
});

test('a blocked task keeps its reason, hands over to the next one, and unblocks to pending', () => {
  let state = apply(three(), { op: 'block', id: 1, reason: 'needs the API key' });
  assert.equal(statuses(state), '1:blocked 2:in_progress 3:pending');
  assert.equal(state.todos[0].reason, 'needs the API key');
  state = apply(state, { op: 'unblock', id: 1 });
  assert.equal(statuses(state), '1:pending 2:in_progress 3:pending');
  assert.equal(state.todos[0].reason, undefined);
  assert.throws(() => apply(three(), { op: 'block', id: 1 }), /reason/);
  assert.throws(() => apply(three(), { op: 'unblock', id: 2 }), /not blocked/);
});

test('add appends pending tasks without disturbing the current one, and ids are never reused', () => {
  let state = apply(three(), { op: 'add', items: ['review'] });
  assert.equal(statuses(state), '1:in_progress 2:pending 3:pending 4:pending');
  state = apply(state, { op: 'remove', id: 4 });
  state = apply(state, { op: 'add', items: ['ship'] });
  assert.equal(statuses(state), '1:in_progress 2:pending 3:pending 5:pending');
  const finished = apply(apply(emptyState(), { op: 'init', items: ['a'] }), { op: 'done', id: 1 });
  assert.equal(statuses(apply(finished, { op: 'add', items: ['b'] })), '1:done 2:in_progress');
});

test('removing the current task starts the next one', () => {
  assert.equal(statuses(apply(three(), { op: 'remove', id: 1 })), '2:in_progress 3:pending');
});

test('a request that cannot apply is refused and leaves the state as it was', () => {
  const before = three();
  const snapshot = JSON.stringify(before);
  for (const input of [
    { op: 'done', id: 9 }, { op: 'start' }, { op: 'init', items: [] }, { op: 'init' }, { op: 'add', items: ['  '] },
    { op: 'init', items: ['x'.repeat(301)] }, { op: 'init', items: Array.from({ length: 101 }, (_, i) => `t${i}`) }, { op: 'fly' },
  ]) assert.throws(() => apply(before, input), Error, JSON.stringify(input).slice(0, 40));
  assert.equal(JSON.stringify(before), snapshot);
});

test('view changes nothing, and the list reads as a checklist with its progress', () => {
  const state = apply(apply(three(), { op: 'done', id: 1 }), { op: 'block', id: 3, reason: 'waits on docs' });
  assert.equal(apply(state, { op: 'view' }), state);
  assert.equal(formatTodos(state), [
    'Todos: 1/3 done',
    '[x] #1 write test',
    '[>] #2 implement',
    '[!] #3 document (blocked: waits on docs)',
  ].join('\n'));
  assert.equal(formatTodos(emptyState()), 'No todos.');
  assert.deepEqual(progress(state), { done: 1, total: 3, current: state.todos[1] });
});

test('the latest todo result on the branch is the state; failed, malformed and other results are ignored', () => {
  const result = (toolName, details) => ({ type: 'message', message: { role: 'toolResult', toolName, details } });
  const first = apply(emptyState(), { op: 'init', items: ['a', 'b'] });
  const second = apply(first, { op: 'done', id: 1 });
  const entries = [
    { type: 'message', message: { role: 'user', content: 'go' } },
    result('todo', first),
    result('bash', { todos: [], nextId: 99 }),
    result('todo', second),
    result('todo', undefined),
    result('todo', { todos: 'nope', nextId: 'x' }),
    { type: 'compaction' },
  ];
  assert.deepEqual(stateFromEntries(entries), second);
  assert.deepEqual(stateFromEntries([]), emptyState());
  assert.deepEqual(stateFromEntries([result('todo', first)]), first);
});

const plain = { done: text => `d|${text}`, active: text => `a|${text}`, pending: text => `p|${text}`, blocked: text => `b|${text}`, dim: text => `m|${text}` };

test('the panel lists a short list as it stands and is empty when there is nothing left to do', () => {
  assert.deepEqual(panelLines(emptyState(), plain), []);
  assert.deepEqual(panelLines(three(), plain), ['a|● write test', 'p|○ implement', 'p|○ document']);
  let state = apply(apply(three(), { op: 'done', id: 1 }), { op: 'block', id: 2, reason: 'needs the key' });
  assert.deepEqual(panelLines(state, plain), ['d|✓ write test', 'b|✗ implement — blocked: needs the key', 'a|● document']);
  state = apply(apply(apply(three(), { op: 'done', id: 1 }), { op: 'done', id: 2 }), { op: 'done', id: 3 });
  assert.deepEqual(panelLines(state, plain), [], 'a finished list leaves no panel');
});

test('a long list folds its finished tasks and its tail and keeps the task in progress in view', () => {
  const items = Array.from({ length: 12 }, (_, i) => `task ${i + 1}`);
  let state = apply(emptyState(), { op: 'init', items });
  for (const id of [1, 2, 3, 4]) state = apply(state, { op: 'done', id });
  const lines = panelLines(state, plain, 7);
  assert.equal(lines.length, 7);
  assert.equal(lines[0], 'm|✓ 4 done');
  assert.equal(lines[1], 'a|● task 5', 'the task in progress comes first among the open ones');
  assert.equal(lines.at(-1), 'm|… +3 more', 'five of the eight open tasks are shown');
  assert.equal(panelLines(state, plain, 20).length, 12, 'a roomy panel does not fold');
});
