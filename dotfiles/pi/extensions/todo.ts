import { StringEnum } from '@earendil-works/pi-ai';
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';
import { Text, truncateToWidth, type KeyId } from '@earendil-works/pi-tui';
import { Type } from 'typebox';
import { applyTodo, displayText, emptyState, formatTodos, panelLines, progress, stateFromEntries, TODO_ENTRY, type TodoInput, type TodoState } from './todo-core.ts';
import { todoMessages } from './todo-i18n.ts';

const statuses = ['pending', 'in_progress', 'done', 'blocked'] as const;
const nullableText = (maxLength: number) => Type.Union([Type.String({ maxLength }), Type.Null()]);
const dependencies = Type.Array(Type.Integer({ minimum: 1 }), { maxItems: 100 });
const fields = {
  description: Type.Optional(nullableText(4000)), activeForm: Type.Optional(nullableText(300)),
  owner: Type.Optional(nullableText(300)), metadata: Type.Optional(Type.Union([Type.Record(Type.String(), Type.Unknown()), Type.Null()])),
  blockedBy: Type.Optional(dependencies),
};
const Parameters = Type.Object({
  op: StringEnum(['init', 'add', 'start', 'done', 'block', 'unblock', 'remove', 'update', 'get', 'clear', 'view'] as const),
  items: Type.Optional(Type.Array(Type.Union([
    Type.String({ minLength: 1, maxLength: 300 }),
    Type.Object({ text: Type.String({ minLength: 1, maxLength: 300 }), ...fields }),
  ]), { minItems: 1, maxItems: 100 })),
  id: Type.Optional(Type.Integer({ minimum: 1 })), reason: Type.Optional(Type.String({ maxLength: 1000 })),
  text: Type.Optional(Type.String({ minLength: 1, maxLength: 300 })), ...fields,
  addBlockedBy: Type.Optional(dependencies), removeBlockedBy: Type.Optional(dependencies),
  status: Type.Optional(StringEnum(statuses)), query: Type.Optional(Type.String({ maxLength: 1000 })),
});

export type TodoOptions = { maxWidgetLines?: number; collapseKey?: string | null; locale?: string; hideCompleted?: boolean };
type Slot = {
  state: TodoState; collapsed: boolean; hidden: Set<number>; ctx?: ExtensionContext;
};

function optionsOf(options: TodoOptions) {
  const maxWidgetLines = options.maxWidgetLines ?? 8;
  if (!Number.isInteger(maxWidgetLines) || maxWidgetLines < 3 || maxWidgetLines > 101) throw new Error('maxWidgetLines must be an integer between 3 and 101');
  const collapseKey = options.collapseKey === undefined ? 'ctrl+shift+t' : options.collapseKey?.trim().toLowerCase();
  if (collapseKey) {
    const parts = collapseKey.split('+'), key = parts.pop() ?? '';
    if (new Set(parts).size !== parts.length || parts.some(part => !['ctrl', 'alt', 'shift', 'super'].includes(part))
      || !/^(?:[a-z0-9]|[\]\/.,;`'\\=\-]|escape|enter|tab|space|backspace|delete|insert|home|end|pageup|pagedown|up|down|left|right|f(?:[1-9]|1[0-2]))$/.test(key)) {
      throw new Error('Invalid todo collapse shortcut key');
    }
  } else if (options.collapseKey !== null) throw new Error('Use null to disable the todo collapse shortcut');
  return { maxWidgetLines, collapseKey, hideCompleted: options.hideCompleted ?? false, messages: todoMessages(options.locale) };
}

function queryOf(args: string): TodoInput {
  const words = args.trim().split(/\s+/).filter(Boolean), input: TodoInput = { op: 'view' }, query = [];
  if (statuses.includes(words[0] as typeof statuses[number])) input.status = words.shift();
  for (const word of words) {
    if (word.startsWith('owner=')) input.owner = word.slice(6); else query.push(word);
  }
  if (query.length) input.query = query.join(' ');
  return input;
}

export function createTodo(pi: ExtensionAPI, options: TodoOptions = {}) {
  const config = optionsOf(options), messages = config.messages;
  const sessions = new Map<string, Slot>();
  let foreground: string | undefined;
  const idOf = (ctx: ExtensionContext) => ctx.sessionManager.getSessionId();
  const slotOf = (ctx: ExtensionContext) => {
    const id = idOf(ctx);
    let slot = sessions.get(id);
    if (!slot) { slot = { state: emptyState(), collapsed: false, hidden: new Set() }; sessions.set(id, slot); }
    return slot;
  };

  const show = (ctx: ExtensionContext, slot: Slot) => {
    if (!ctx.hasUI) return;
    const { done, total, current } = progress(slot.state), open = total > done;
    if (ctx.mode !== 'tui') {
      ctx.ui.setStatus('todo', open ? `${messages.title} ${done}/${total}${current ? ` · ${displayText(current.text).slice(0, 40)}` : ''}` : undefined);
      return;
    }
    if (foreground !== idOf(ctx)) return;
    slot.ctx = ctx;
    ctx.ui.setStatus('todo', undefined);
    if (!open) { ctx.ui.setWidget('todo', undefined); return; }
    ctx.ui.setWidget('todo', (_tui, theme) => ({
      invalidate() {},
      render(width: number) {
        if (!slot.ctx || width < 1) return [];
        const ui = slot.ctx.ui, colors = ui.theme ?? theme;
        const counts = progress(slot.state);
        if (counts.total === counts.done) return [];
        const expanded = ui.getToolsExpanded?.() === true;
        const heading = colors.fg('accent', `${messages.title} (${counts.done}/${counts.total})`);
        const hint = config.collapseKey ? messages.expandHint.replace('{key}', config.collapseKey) : messages.collapsed;
        const style = {
          done: (s: string) => colors.fg('dim', s), active: (s: string) => colors.fg('accent', s),
          pending: (s: string) => colors.fg('muted', s), blocked: (s: string) => colors.fg('warning', s), dim: (s: string) => colors.fg('dim', s),
        };
        const visible = { ...slot.state, todos: slot.state.todos.filter(todo => todo.status !== 'done' || !slot.hidden.has(todo.id)) };
        const body = slot.collapsed && !expanded ? [colors.fg('dim', hint)]
          : panelLines(visible, style, expanded ? 100 : config.maxWidgetLines - 1, messages);
        return [...[heading, ...body].map(line => truncateToWidth('   ' + line, width, '…')), ''];
      },
    }), { placement: 'aboveEditor' });
  };

  const restore = (ctx: ExtensionContext) => {
    const slot = slotOf(ctx);
    slot.state = stateFromEntries(ctx.sessionManager.getBranch());
    slot.hidden.clear();
    if (foreground === undefined && ctx.hasUI) foreground = idOf(ctx);
    show(ctx, slot);
  };
  pi.on('session_start', async (_event, ctx) => restore(ctx));
  pi.on('session_tree', async (_event, ctx) => restore(ctx));
  pi.on('session_compact', async (_event, ctx) => restore(ctx));
  pi.on('session_shutdown', async (_event, ctx) => {
    const id = idOf(ctx), slot = sessions.get(id);
    if (slot) slot.ctx = undefined;
    sessions.delete(id);
    if (foreground !== id) return;
    foreground = undefined;
    try {
      if (ctx.hasUI) { ctx.ui.setWidget('todo', undefined); ctx.ui.setStatus('todo', undefined); }
    } catch { /* The old UI may already have been retired. */ }
  });
  pi.on('agent_start', async (_event, ctx) => {
    if (!config.hideCompleted || foreground !== idOf(ctx)) return;
    const slot = slotOf(ctx);
    for (const todo of slot.state.todos) if (todo.status === 'done') slot.hidden.add(todo.id);
    show(ctx, slot);
  });

  if (config.collapseKey) pi.registerShortcut(config.collapseKey as KeyId, {
    description: messages.collapse,
    handler: async ctx => {
      if (ctx.mode !== 'tui' || foreground !== idOf(ctx)) return;
      const slot = slotOf(ctx);
      slot.collapsed = !slot.collapsed;
      show(ctx, slot);
    },
  });

  pi.registerTool({
    name: 'todo', label: 'Todo',
    description: 'Keep a branch-persistent task list. init/add accept strings or task objects. start/done/block/unblock/remove preserve one active task and auto-advance; block requires a reason. update edits text, description, activeForm, owner, metadata and dependencies. get shows one task; view filters by status, owner or query; clear resets the list. Dependencies annotate work, not scheduling gates. Invalid operations fail without changing the list.',
    promptSnippet: 'todo: task tracking with workflow operations, editable metadata, dependencies, filtered view and get',
    promptGuidelines: [
      'For work with several steps, init a todo list first, mark each task done as soon as it is finished, and view the list after compaction instead of trusting memory.',
      'Use blockedBy task IDs for dependencies and block with a reason for external blockers. Dependencies are advisory; remove references before removing a prerequisite.',
      'Use update to edit text/description/activeForm/owner, merge metadata keys (null removes a key), or addBlockedBy/removeBlockedBy. Filtered reads never replace the full list.',
    ],
    parameters: Parameters, executionMode: 'sequential',
    async execute(_id, params, _signal, _update, ctx) {
      const slot = slotOf(ctx), next = applyTodo(slot.state, params);
      if (params.op !== 'view' && params.op !== 'get' && JSON.stringify(next) !== JSON.stringify(slot.state)) {
        pi.appendEntry(TODO_ENTRY, { version: 1, state: next });
      }
      slot.state = next;
      if (params.op === 'init' || params.op === 'clear') slot.hidden.clear();
      show(ctx, slot);
      return { content: [{ type: 'text', text: formatTodos(next, params) }], details: JSON.parse(JSON.stringify(next)) };
    },
    renderCall(args, theme) {
      const detail = args.items ? `${args.items.length} task${args.items.length === 1 ? '' : 's'}` : args.id !== undefined ? `#${args.id}` : '';
      return new Text(theme.fg('toolTitle', theme.bold('todo ')) + theme.fg('accent', args.op) + (detail ? theme.fg('muted', ` ${detail}`) : ''), 0, 0);
    },
  });
  pi.registerCommand('todos', {
    description: messages.command,
    handler: async (args, ctx) => {
      const slot = slotOf(ctx), query = queryOf(args);
      applyTodo(slot.state, query);
      if (ctx.hasUI) ctx.ui.notify(formatTodos(slot.state, query, messages), 'info');
    },
  });
}

export default function (pi: ExtensionAPI) { createTodo(pi); }
