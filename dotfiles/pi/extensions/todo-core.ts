export type Status = 'pending' | 'in_progress' | 'done' | 'blocked';
export type Todo = { id: number; text: string; status: Status; reason?: string };
export type TodoState = { todos: Todo[]; nextId: number };
export type TodoInput = { op?: string; items?: unknown; id?: unknown; reason?: unknown };

const MAX_TODOS = 100;
const MAX_TEXT = 300;
const STATUSES: readonly string[] = ['pending', 'in_progress', 'done', 'blocked'];

export const emptyState = (): TodoState => ({ todos: [], nextId: 1 });

/** Exactly one task is in progress while any is pending: when none is, the first pending one is. */
function settle(todos: Todo[]): Todo[] {
  if (todos.some(todo => todo.status === 'in_progress')) return todos;
  const next = todos.find(todo => todo.status === 'pending');
  return next ? todos.map(todo => (todo === next ? { ...todo, status: 'in_progress' as const } : todo)) : todos;
}

function texts(items: unknown): string[] {
  if (!Array.isArray(items) || items.length === 0) throw new Error('`items` must list at least one task');
  return items.map(item => {
    const text = typeof item === 'string' ? item.trim() : '';
    if (text === '') throw new Error('A task needs text');
    if (text.length > MAX_TEXT) throw new Error(`A task is limited to ${MAX_TEXT} characters`);
    return text;
  });
}

function target(state: TodoState, id: unknown): Todo {
  if (typeof id !== 'number' || !Number.isInteger(id)) throw new Error('This operation needs the numeric task `id`');
  const todo = state.todos.find(candidate => candidate.id === id);
  if (!todo) throw new Error(`Todo #${id} does not exist`);
  return todo;
}

function replace(state: TodoState, id: number, change: (todo: Todo) => Todo): Todo[] {
  return state.todos.map(todo => (todo.id === id ? change(todo) : todo));
}

function without(todo: Todo, key: 'reason'): Todo {
  const { [key]: _dropped, ...rest } = todo;
  return rest;
}

/** The state after one operation. Pure: a request that cannot apply throws and the caller keeps the old state. */
export function applyTodo(state: TodoState, input: TodoInput): TodoState {
  switch (input.op) {
    case 'view':
      return state;
    case 'init': {
      const items = texts(input.items);
      if (items.length > MAX_TODOS) throw new Error(`A list is limited to ${MAX_TODOS} tasks`);
      const todos = items.map((text, index): Todo => ({ id: index + 1, text, status: 'pending' }));
      return { todos: settle(todos), nextId: items.length + 1 };
    }
    case 'add': {
      const items = texts(input.items);
      if (state.todos.length + items.length > MAX_TODOS) throw new Error(`A list is limited to ${MAX_TODOS} tasks`);
      const added = items.map((text, index): Todo => ({ id: state.nextId + index, text, status: 'pending' }));
      return { todos: settle([...state.todos, ...added]), nextId: state.nextId + items.length };
    }
    case 'start': {
      const { id } = target(state, input.id);
      const todos = state.todos.map((todo): Todo => {
        if (todo.id === id) return without({ ...todo, status: 'in_progress' }, 'reason');
        return todo.status === 'in_progress' ? { ...todo, status: 'pending' } : todo;
      });
      return { ...state, todos };
    }
    case 'done': {
      const { id } = target(state, input.id);
      return { ...state, todos: settle(replace(state, id, todo => without({ ...todo, status: 'done' }, 'reason'))) };
    }
    case 'block': {
      const { id } = target(state, input.id);
      const reason = typeof input.reason === 'string' ? input.reason.trim() : '';
      if (reason === '') throw new Error('Blocking a task needs a `reason`');
      return { ...state, todos: settle(replace(state, id, todo => ({ ...todo, status: 'blocked', reason }))) };
    }
    case 'unblock': {
      const todo = target(state, input.id);
      if (todo.status !== 'blocked') throw new Error(`Todo #${todo.id} is not blocked`);
      return { ...state, todos: settle(replace(state, todo.id, current => without({ ...current, status: 'pending' }, 'reason'))) };
    }
    case 'remove': {
      const { id } = target(state, input.id);
      return { ...state, todos: settle(state.todos.filter(todo => todo.id !== id)) };
    }
    default:
      throw new Error(`Unknown operation "${String(input.op)}"; use init, add, start, done, block, unblock, remove or view`);
  }
}

export function progress(state: TodoState): { done: number; total: number; current: Todo | undefined } {
  return {
    done: state.todos.filter(todo => todo.status === 'done').length,
    total: state.todos.length,
    current: state.todos.find(todo => todo.status === 'in_progress'),
  };
}

const MARKS: Record<Status, string> = { done: '[x]', in_progress: '[>]', pending: '[ ]', blocked: '[!]' };

export function formatTodos(state: TodoState): string {
  if (state.todos.length === 0) return 'No todos.';
  const { done, total } = progress(state);
  const lines = state.todos.map(todo => `${MARKS[todo.status]} #${todo.id} ${todo.text}${todo.status === 'blocked' ? ` (blocked: ${todo.reason})` : ''}`);
  return [`Todos: ${done}/${total} done`, ...lines].join('\n');
}

export interface PanelStyle {
  done: (text: string) => string;
  active: (text: string) => string;
  pending: (text: string) => string;
  blocked: (text: string) => string;
  dim: (text: string) => string;
}

/**
 * The checklist shown above the editor while work is under way: empty when the list is empty or finished. A long list
 * folds its finished tasks into one `✓ N done` line and then its tail into `… +K more`, so the panel never grows past
 * `maxRows` lines and always keeps the task in progress in view.
 */
export function panelLines(state: TodoState, style: PanelStyle, maxRows = 7): string[] {
  const { done, total } = progress(state);
  if (total === 0 || done === total) return [];
  const row = (todo: Todo): string => {
    switch (todo.status) {
      case 'done':
        return style.done(`✓ ${todo.text}`);
      case 'in_progress':
        return style.active(`● ${todo.text}`);
      case 'blocked':
        return style.blocked(`✗ ${todo.text} — blocked: ${todo.reason ?? 'no reason given'}`);
      default:
        return style.pending(`○ ${todo.text}`);
    }
  };
  if (state.todos.length <= maxRows) return state.todos.map(row);
  const open = state.todos.filter(todo => todo.status !== 'done');
  const lines = done > 0 ? [style.dim(`✓ ${done} done`)] : [];
  const room = maxRows - lines.length;
  if (open.length <= room) return [...lines, ...open.map(row)];
  // Keep the task in progress visible: window the open tasks so it is the first row shown.
  const first = Math.max(0, open.findIndex(todo => todo.status === 'in_progress'));
  const shown = open.slice(first, first + room - 1);
  const hidden = open.length - shown.length;
  return [...lines, ...shown.map(row), style.dim(`… +${hidden} more`)];
}

function isTodo(value: unknown): value is Todo {
  return typeof value === 'object' && value !== null
    && 'id' in value && typeof value.id === 'number'
    && 'text' in value && typeof value.text === 'string'
    && 'status' in value && typeof value.status === 'string' && STATUSES.includes(value.status)
    && (!('reason' in value) || value.reason === undefined || typeof value.reason === 'string');
}

function isState(value: unknown): value is TodoState {
  return typeof value === 'object' && value !== null
    && 'todos' in value && Array.isArray(value.todos) && value.todos.every(isTodo)
    && 'nextId' in value && typeof value.nextId === 'number' && Number.isInteger(value.nextId) && value.nextId >= 1;
}

/**
 * The list as of the latest successful `todo` result on a session branch. The state lives in tool-result details, so
 * branching with `/tree` and resuming a session restore the list that belongs to that point in the conversation.
 */
export function stateFromEntries(entries: readonly unknown[]): TodoState {
  let state = emptyState();
  for (const entry of entries) {
    if (typeof entry !== 'object' || entry === null || !('type' in entry) || entry.type !== 'message' || !('message' in entry)) continue;
    const message = entry.message;
    if (typeof message !== 'object' || message === null || !('role' in message) || message.role !== 'toolResult') continue;
    if (!('toolName' in message) || message.toolName !== 'todo' || !('details' in message) || !isState(message.details)) continue;
    state = message.details;
  }
  return state;
}
