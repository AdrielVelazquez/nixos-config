import test from 'node:test';
import assert from 'node:assert/strict';
import { applyTodo, emptyState, formatTodos, panelLines, stateFromEntries } from '../../dotfiles/pi/extensions/todo-core.ts';

const init = items => applyTodo(emptyState(), { op: 'init', items });
const update = (state, id, fields) => applyTodo(state, { op: 'update', id, ...fields });
const snapshot = state => ({ type: 'custom', customType: 'pi-todo-state', data: { version: 1, state } });
const result = (state, extra = {}) => ({ type: 'message', message: { role: 'toolResult', toolName: 'todo', details: state, ...extra } });
const plain = Object.fromEntries(['done', 'active', 'pending', 'blocked', 'dim'].map(name => [name, value => value]));

test('rich batch creation preserves legacy strings and starts one task', () => {
  const state = init(['Research', { text: 'Build', description: 'Use the existing API', activeForm: 'building', owner: 'Ada', metadata: { priority: 1 }, blockedBy: [1] }]);
  assert.deepEqual(state.todos[1], { id: 2, text: 'Build', status: 'pending', description: 'Use the existing API', activeForm: 'building', owner: 'Ada', metadata: { priority: 1 }, blockedBy: [1] });
  assert.equal(state.todos.filter(t => t.status === 'in_progress').length, 1);
});

test('update edits text and fields while keeping workflow state and merging metadata', () => {
  let state = init([{ text: 'Old', description: 'Long detail', owner: 'Ada', metadata: { keep: 1, drop: 2 } }]);
  state = update(state, 1, { text: 'New', activeForm: 'working', description: null, owner: null, metadata: { drop: null, added: { ok: true } } });
  assert.deepEqual(state.todos[0], { id: 1, text: 'New', status: 'in_progress', activeForm: 'working', metadata: { keep: 1, added: { ok: true } } });
  state = update(state, 1, { activeForm: null, metadata: null });
  assert.deepEqual(state.todos[0], { id: 1, text: 'New', status: 'in_progress' });
});

test('invalid metadata and text are atomic, bounded and JSON-only', () => {
  const state = init(['One', 'Two']);
  const before = JSON.stringify(state);
  const cyclic = {}; cyclic.self = cyclic;
  for (const fields of [{}, { text: ' ' }, { text: 'x'.repeat(301) }, { description: 'x'.repeat(4001) }, { activeForm: 'x'.repeat(301) }, { owner: 4 }, { metadata: { value: undefined } }, { metadata: { huge: 'x'.repeat(8193) } }, { metadata: cyclic }, { metadata: { value: Infinity } }]) {
    assert.throws(() => update(state, 1, fields), Error);
    assert.equal(JSON.stringify(state), before);
  }
  const bad = [{ text: 'Valid' }, { text: ' ' }];
  assert.throws(() => applyTodo(state, { op: 'add', items: bad }));
  assert.equal(JSON.stringify(state), before);
});

test('metadata is copied and prototype keys remain inert data', () => {
  const metadata = JSON.parse('{"__proto__":{"polluted":true},"nested":{"value":1}}');
  const state = init([{ text: 'Task', metadata }]);
  metadata.nested.value = 9;
  assert.equal(state.todos[0].metadata.nested.value, 1);
  const changed = update(state, 1, { metadata: JSON.parse('{"constructor":"data"}') });
  assert.equal(Object.prototype.polluted, undefined);
  assert.equal(Object.getPrototypeOf(changed.todos[0].metadata), Object.prototype);
  assert.equal(changed.todos[0].metadata.constructor, 'data');
});

test('dependency additions, removal and cycles are validated before committing', () => {
  let state = init(['One', 'Two', 'Three']);
  state = update(state, 2, { addBlockedBy: [1, 1] });
  state = update(state, 3, { addBlockedBy: [2] });
  assert.deepEqual(state.todos[1].blockedBy, [1]);
  const before = JSON.stringify(state);
  for (const [id, fields] of [[1, { addBlockedBy: [3] }], [1, { addBlockedBy: [1] }], [1, { addBlockedBy: [99] }], [1, { addBlockedBy: [1.5] }]]) {
    assert.throws(() => update(state, id, fields));
    assert.equal(JSON.stringify(state), before);
  }
  assert.throws(() => applyTodo(state, { op: 'remove', id: 2 }), /depend|required/i);
  state = update(state, 3, { removeBlockedBy: [2] });
  assert.equal(state.todos[2].blockedBy, undefined);
  assert.equal(applyTodo(state, { op: 'remove', id: 2 }).todos.length, 2);
});

test('batch dependency graphs validate references and cycles atomically', () => {
  const state = init([{ text: 'First', blockedBy: [2] }, { text: 'Second' }]);
  assert.deepEqual(state.todos[0].blockedBy, [2]);
  assert.throws(() => init([{ text: 'First', blockedBy: [2] }, { text: 'Second', blockedBy: [1] }]), /cycl/i);
  assert.throws(() => init([{ text: 'First', blockedBy: [9] }]), /exist|found/i);
});

test('dependency annotations do not replace manual blockers or gate scheduling', () => {
  let state = init([{ text: 'First' }, { text: 'Second', blockedBy: [1] }]);
  state = applyTodo(state, { op: 'start', id: 2 });
  assert.equal(state.todos[1].status, 'in_progress');
  state = applyTodo(state, { op: 'block', id: 2, reason: 'Waiting for credentials' });
  assert.equal(state.todos[1].reason, 'Waiting for credentials');
  assert.deepEqual(state.todos[1].blockedBy, [1]);
});

test('get and filters present a subset but keep the canonical state untouched', () => {
  let state = init([{ text: 'Read docs', owner: 'Ada' }, { text: 'Write tests', description: 'Unit coverage', owner: 'Lin' }]);
  state = applyTodo(state, { op: 'done', id: 1 });
  assert.equal(applyTodo(state, { op: 'get', id: 2 }), state);
  assert.match(formatTodos(state, { op: 'get', id: 2 }), /Unit coverage/);
  assert.doesNotMatch(formatTodos(state, { status: 'pending' }), /Read docs|Write tests/);
  assert.match(formatTodos(state, { owner: 'Ada' }), /Read docs/);
  assert.doesNotMatch(formatTodos(state, { owner: 'Ada' }), /Write tests/);
  assert.match(formatTodos(state, { query: 'COVERAGE' }), /Write tests/);
  assert.throws(() => applyTodo(state, { op: 'get', id: 99 }), /exist/);
  assert.throws(() => applyTodo(state, { op: 'view', status: 'invalid' }));
  assert.deepEqual(applyTodo(state, { op: 'clear' }), emptyState());
});

test('custom snapshots restore nested calls and coexist with legacy details', () => {
  const old = init(['Legacy']);
  const latest = applyTodo(old, { op: 'add', items: ['Nested call'] });
  assert.deepEqual(stateFromEntries([result(old), snapshot(latest)]), latest);
  assert.deepEqual(stateFromEntries([result(old)]), old);
  assert.deepEqual(stateFromEntries([snapshot(latest), result(old, { isError: true })]), latest);
  assert.deepEqual(stateFromEntries([snapshot(old)]), old);
});

test('replay rejects malformed versions, duplicate ids, cycles and bad nextId', () => {
  const valid = init(['Good']);
  const invalid = [
    { todos: [{ id: 1, text: 'Bad', status: 'pending' }, { id: 1, text: 'Duplicate', status: 'pending' }], nextId: 3 },
    { todos: [{ id: 1, text: 'Bad', status: 'pending', blockedBy: [1] }], nextId: 2 },
    { todos: [{ id: 1, text: 'Bad', status: 'pending' }], nextId: 1 },
    { todos: [{ id: 1, text: 'Bad', status: 'pending', metadata: { n: undefined } }], nextId: 2 },
  ];
  for (const value of invalid) assert.deepEqual(stateFromEntries([snapshot(valid), snapshot(value)]), valid);
  assert.deepEqual(stateFromEntries([snapshot(valid), { type: 'custom', customType: 'pi-todo-state', data: { version: 99, state: emptyState() } }]), valid);
});

test('replayed snapshots do not alias mutable branch data', () => {
  const state = init([{ text: 'Safe', metadata: { nested: { value: 1 } } }]);
  const restored = stateFromEntries([snapshot(state)]);
  restored.todos[0].text = 'Changed';
  restored.todos[0].metadata.nested.value = 5;
  assert.equal(state.todos[0].text, 'Safe');
  assert.equal(state.todos[0].metadata.nested.value, 1);
});

test('panel adds activity and dependency annotations without losing the active task', () => {
  let state = init([{ text: 'First' }, { text: 'Second', activeForm: 'building', blockedBy: [1], owner: 'Ada' }]);
  state = applyTodo(state, { op: 'start', id: 2 });
  const lines = panelLines(state, plain);
  assert.match(lines[1], /Second.*building/);
  assert.match(lines[1], /#1/);
  assert.match(lines[1], /Ada/);
});
