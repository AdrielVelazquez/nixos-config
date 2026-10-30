export type Status = 'pending' | 'in_progress' | 'done' | 'blocked';
export type Todo = {
  id: number; text: string; status: Status; reason?: string;
  description?: string; activeForm?: string; owner?: string;
  metadata?: Record<string, unknown>; blockedBy?: number[];
};
export type TodoState = { todos: Todo[]; nextId: number };
export type TodoInput = {
  op?: string; items?: unknown; id?: unknown; reason?: unknown; text?: unknown;
  description?: unknown; activeForm?: unknown; owner?: unknown; metadata?: unknown;
  blockedBy?: unknown; addBlockedBy?: unknown; removeBlockedBy?: unknown;
  status?: unknown; query?: unknown;
};
export const TODO_ENTRY = 'pi-todo-state';
const MAX_TODOS = 100;
const STATUSES: readonly string[] = ['pending', 'in_progress', 'done', 'blocked'];
const FIELDS = { description: 4000, activeForm: 300, owner: 300 } as const;
export const emptyState = (): TodoState => ({ todos: [], nextId: 1 });

function object(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
    && [Object.prototype, null].includes(Object.getPrototypeOf(value));
}

function text(value: unknown, name: string, max: number, required = false): string {
  if (typeof value !== 'string') throw new Error(`${name} must be text`);
  const result = value.trim();
  if (required && result === '') throw new Error('A task needs text');
  if (result.length > max) throw new Error(`${name} is limited to ${max} characters`);
  return result;
}

function json(value: unknown, parents = new Set<unknown>(), depth = 0): void {
  if (depth > 12) throw new Error('Metadata is nested too deeply');
  if (value === null || typeof value === 'string' || typeof value === 'boolean') return;
  if (typeof value === 'number' && Number.isFinite(value)) return;
  if ((!Array.isArray(value) && !object(value)) || parents.has(value)) throw new Error('Metadata must be acyclic JSON');
  parents.add(value);
  for (const item of Object.values(value as object)) json(item, parents, depth + 1);
  parents.delete(value);
}

function metadata(value: unknown): Record<string, unknown> {
  if (!object(value)) throw new Error('Metadata must be a JSON object');
  json(value);
  const encoded = JSON.stringify(value);
  if (new TextEncoder().encode(encoded).length > 8192) throw new Error('Metadata is limited to 8192 JSON bytes');
  return JSON.parse(encoded);
}

function ids(value: unknown): number[] {
  if (!Array.isArray(value) || value.length > MAX_TODOS || value.some(id => !Number.isSafeInteger(id) || id <= 0)) {
    throw new Error('Dependencies must be a list of positive integer task ids');
  }
  return [...new Set(value)];
}

function graph(todos: Todo[]): void {
  const byId = new Map(todos.map(todo => [todo.id, todo]));
  const visiting = new Set<number>(), visited = new Set<number>();
  const visit = (id: number) => {
    if (visiting.has(id)) throw new Error('Task dependencies cannot contain a cycle');
    if (visited.has(id)) return;
    visiting.add(id);
    for (const dependency of byId.get(id)?.blockedBy ?? []) {
      if (!byId.has(dependency)) throw new Error(`Dependency #${dependency} does not exist`);
      visit(dependency);
    }
    visiting.delete(id);
    visited.add(id);
  };
  for (const todo of todos) visit(todo.id);
}

/** Exactly one task is in progress while any is pending; dependencies are annotations, not scheduling gates. */
function settle(todos: Todo[]): Todo[] {
  if (todos.some(todo => todo.status === 'in_progress')) return todos;
  const next = todos.find(todo => todo.status === 'pending');
  return next ? todos.map(todo => todo === next ? { ...todo, status: 'in_progress' } : todo) : todos;
}

function target(state: TodoState, id: unknown): Todo {
  if (!Number.isSafeInteger(id)) throw new Error('This operation needs the numeric task `id`');
  const todo = state.todos.find(candidate => candidate.id === id);
  if (!todo) throw new Error(`Todo #${id} does not exist`);
  return todo;
}

function fields(todo: Todo, input: TodoInput): Todo {
  const next = { ...todo };
  if (input.text !== undefined) next.text = text(input.text, 'A task', 300, true);
  for (const [name, max] of Object.entries(FIELDS) as [keyof typeof FIELDS, number][]) {
    if (input[name] === undefined) continue;
    const value = input[name] === null ? '' : text(input[name], name, max);
    if (value) next[name] = value; else delete next[name];
  }
  if (input.metadata !== undefined) {
    if (input.metadata === null) delete next.metadata;
    else {
      const merged = { ...next.metadata, ...metadata(input.metadata) };
      const kept = Object.fromEntries(Object.entries(merged).filter(([, value]) => value !== null));
      if (Object.keys(kept).length) next.metadata = metadata(kept); else delete next.metadata;
    }
  }
  let dependencies = [...(next.blockedBy ?? [])];
  if (input.blockedBy !== undefined) dependencies = ids(input.blockedBy);
  if (input.removeBlockedBy !== undefined) {
    const removed = new Set(ids(input.removeBlockedBy));
    dependencies = dependencies.filter(id => !removed.has(id));
  }
  if (input.addBlockedBy !== undefined) dependencies = [...new Set([...dependencies, ...ids(input.addBlockedBy)])];
  if (dependencies.length) next.blockedBy = dependencies; else delete next.blockedBy;
  return next;
}

function items(input: unknown, nextId: number): Todo[] {
  if (!Array.isArray(input) || input.length === 0) throw new Error('`items` must list at least one task');
  return input.map((item, index) => {
    const spec = typeof item === 'string' ? { text: item } : item;
    if (!object(spec)) throw new Error('A task needs text');
    return fields({ id: nextId + index, text: text(spec.text, 'A task', 300, true), status: 'pending' }, spec);
  });
}

function selected(state: TodoState, input: TodoInput): Todo[] {
  if (input.status !== undefined && !STATUSES.includes(input.status as string)) throw new Error('Unknown todo status filter');
  const owner = input.owner === undefined ? undefined : text(input.owner, 'Owner filter', 300);
  const query = input.query === undefined ? '' : text(input.query, 'Query', 1000).toLocaleLowerCase();
  return (input.op === 'get' ? [target(state, input.id)] : state.todos).filter(todo =>
    (input.status === undefined || todo.status === input.status)
    && (owner === undefined || todo.owner === owner)
    && (!query || [todo.text, todo.description, todo.activeForm, todo.reason, todo.owner].some(value => value?.toLocaleLowerCase().includes(query))));
}

/** Pure and atomic: invalid operations throw before the caller replaces its state. */
export function applyTodo(state: TodoState, input: TodoInput): TodoState {
  if (input.op === 'view' || input.op === 'get') { selected(state, input); return state; }
  if (input.op === 'clear') return emptyState();
  if (input.op === 'init' || input.op === 'add') {
    const added = items(input.items, input.op === 'init' ? 1 : state.nextId);
    const todos = input.op === 'init' ? added : [...state.todos, ...added];
    if (todos.length > MAX_TODOS) throw new Error(`A list is limited to ${MAX_TODOS} tasks`);
    graph(todos);
    return { todos: settle(todos), nextId: input.op === 'init' ? added.length + 1 : state.nextId + added.length };
  }
  if (!['start', 'done', 'block', 'unblock', 'remove', 'update'].includes(input.op ?? '')) {
    throw new Error(`Unknown operation "${String(input.op)}"; use init, add, start, done, block, unblock, remove, update, get, clear or view`);
  }
  const current = target(state, input.id);
  let changed = { ...current };
  if (input.op === 'remove') {
    if (state.todos.some(todo => todo.blockedBy?.includes(current.id))) throw new Error(`Todo #${current.id} is required by another task dependency`);
    return { ...state, todos: settle(state.todos.filter(todo => todo.id !== current.id)) };
  }
  if (input.op === 'update') {
    if (!['text', ...Object.keys(FIELDS), 'metadata', 'blockedBy', 'addBlockedBy', 'removeBlockedBy'].some(key => input[key as keyof TodoInput] !== undefined)) {
      throw new Error('Updating a task needs at least one editable field');
    }
    changed = fields(current, input);
  } else {
    if (input.op === 'unblock' && current.status !== 'blocked') throw new Error(`Todo #${current.id} is not blocked`);
    changed.status = input.op === 'start' ? 'in_progress' : input.op === 'done' ? 'done' : input.op === 'block' ? 'blocked' : 'pending';
    if (input.op === 'block') {
      const reason = typeof input.reason === 'string' ? text(input.reason, 'Blocked reason', 1000) : '';
      if (!reason) throw new Error('Blocking a task needs a `reason`');
      changed.reason = reason;
    } else delete changed.reason;
  }
  const todos = state.todos.map(todo => todo.id === current.id ? changed
    : input.op === 'start' && todo.status === 'in_progress' ? { ...todo, status: 'pending' as const } : todo);
  graph(todos);
  return { ...state, todos: settle(todos) };
}

export function progress(state: TodoState): { done: number; total: number; current: Todo | undefined } {
  return { done: state.todos.filter(todo => todo.status === 'done').length, total: state.todos.length, current: state.todos.find(todo => todo.status === 'in_progress') };
}

export function displayText(value: string): string {
  return value.replace(/\x1b(?:\[[0-?]*[ -/]*[@-~]|\][^\x07\x1b]*(?:\x07|\x1b\\))/g, '').replace(/[\x00-\x1f\x7f-\x9f]/g, ' ');
}

const MARKS: Record<Status, string> = { done: '[x]', in_progress: '[>]', pending: '[ ]', blocked: '[!]' };
const ENGLISH = { title: 'Todos', done: 'done', blocked: 'blocked', empty: 'No todos.', noMatches: 'No matching todos.', activity: 'activity', owner: 'owner', dependencies: 'depends on', metadata: 'metadata' };
export function formatTodos(state: TodoState, input: TodoInput = {}, labels = ENGLISH): string {
  if (state.todos.length === 0) return labels.empty;
  const shown = selected(state, input);
  if (shown.length === 0) return labels.noMatches;
  const { done, total } = progress(state);
  const lines = shown.flatMap(todo => {
    const row = `${MARKS[todo.status]} #${todo.id} ${displayText(todo.text)}${todo.status === 'blocked' ? ` (${labels.blocked}: ${displayText(todo.reason ?? '')})` : ''}`;
    const extra = [todo.activeForm && `${labels.activity}: ${displayText(todo.activeForm)}`, todo.owner && `${labels.owner}: ${displayText(todo.owner)}`, todo.blockedBy?.length && `${labels.dependencies}: ${todo.blockedBy.map(id => `#${id}`).join(', ')}`].filter(Boolean);
    return [row + (extra.length ? ` (${extra.join('; ')})` : ''), ...(input.op === 'get' ? [todo.description && `  ${displayText(todo.description)}`, todo.metadata && `  ${labels.metadata}: ${JSON.stringify(todo.metadata)}`].filter(Boolean) as string[] : [])];
  });
  return [`${labels.title}: ${done}/${total} ${labels.done}`, ...lines].join('\n');
}

export interface PanelStyle {
  done: (text: string) => string; active: (text: string) => string; pending: (text: string) => string;
  blocked: (text: string) => string; dim: (text: string) => string;
}

export function panelLines(state: TodoState, style: PanelStyle, maxRows = 7, labels = { done: 'done', blocked: 'blocked', more: 'more' }): string[] {
  const { done, total } = progress(state);
  if (total === 0 || done === total) return [];
  const row = (todo: Todo): string => {
    const label = displayText(todo.text) + (todo.status === 'in_progress' && todo.activeForm ? ` (${displayText(todo.activeForm)})` : '')
      + (todo.owner ? ` @${displayText(todo.owner)}` : '') + (todo.blockedBy?.length ? ` ⛓ ${todo.blockedBy.map(id => `#${id}`).join(',')}` : '');
    switch (todo.status) {
      case 'done': return style.done(`✓ ${label}`);
      case 'in_progress': return style.active(`● ${label}`);
      case 'blocked': return style.blocked(`✗ ${label} — ${labels.blocked}: ${displayText(todo.reason ?? 'no reason given')}`);
      default: return style.pending(`○ ${label}`);
    }
  };
  if (state.todos.length <= maxRows) return state.todos.map(row);
  const open = state.todos.filter(todo => todo.status !== 'done');
  const lines = done > 0 && maxRows >= 3 ? [style.dim(`✓ ${done} ${labels.done}`)] : [];
  const room = maxRows - lines.length;
  if (open.length <= room) return [...lines, ...open.map(row)];
  const first = Math.max(0, open.findIndex(todo => todo.status === 'in_progress'));
  const shown = open.slice(first, first + room - 1);
  return [...lines, ...shown.map(row), style.dim(`… +${open.length - shown.length} ${labels.more}`)];
}

function validState(value: unknown): value is TodoState {
  if (!object(value) || !Array.isArray(value.todos) || value.todos.length > MAX_TODOS || !Number.isSafeInteger(value.nextId) || (value.nextId as number) < 1) return false;
  try {
    const seen = new Set<number>();
    let active = 0;
    for (const todo of value.todos) {
      if (!object(todo) || !Number.isSafeInteger(todo.id) || (todo.id as number) < 1 || (todo.id as number) >= (value.nextId as number) || seen.has(todo.id as number) || !STATUSES.includes(todo.status as string)) return false;
      seen.add(todo.id as number);
      text(todo.text, 'A task', 300, true);
      fields(todo as Todo, todo);
      if (todo.reason !== undefined && typeof todo.reason !== 'string') return false;
      if (todo.status === 'in_progress') active++;
    }
    graph(value.todos as Todo[]);
    return active <= 1;
  } catch { return false; }
}

/** Custom snapshots cover nested tools; legacy standalone results remain readable. */
export function stateFromEntries(entries: readonly unknown[]): TodoState {
  let state = emptyState();
  for (const entry of entries) {
    if (!object(entry)) continue;
    let candidate: unknown;
    if (entry.type === 'custom' && entry.customType === TODO_ENTRY && object(entry.data) && entry.data.version === 1) candidate = entry.data.state;
    else if (entry.type === 'message' && object(entry.message) && entry.message.role === 'toolResult' && entry.message.toolName === 'todo' && entry.message.isError !== true) candidate = entry.message.details;
    if (validState(candidate)) state = JSON.parse(JSON.stringify(candidate));
  }
  return state;
}
