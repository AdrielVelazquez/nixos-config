import { StringEnum } from '@earendil-works/pi-ai';
import type { ExtensionAPI, ExtensionContext } from '@earendil-works/pi-coding-agent';
import { Text } from '@earendil-works/pi-tui';
import { Type } from 'typebox';
import { applyTodo, emptyState, formatTodos, progress, stateFromEntries, type TodoState } from './todo-core.ts';

const Parameters = Type.Object({
  op: StringEnum(['init', 'add', 'start', 'done', 'block', 'unblock', 'remove', 'view'] as const, {
    description: 'init replaces the list; add appends; start, done, block, unblock and remove act on `id`; view only shows it.',
  }),
  items: Type.Optional(Type.Array(Type.String(), { description: 'Task texts, for init and add.' })),
  id: Type.Optional(Type.Number({ description: 'The task number shown as #id, for start, done, block, unblock and remove.' })),
  reason: Type.Optional(Type.String({ description: 'Why the task is blocked, for block.' })),
});

/**
 * A task list for the model. The list lives in the details of each `todo` result, so `/tree` branches and resumed
 * sessions get the list that belongs to their point in the conversation.
 */
export default function (pi: ExtensionAPI) {
  let state: TodoState = emptyState();

  const show = (ctx: ExtensionContext) => {
    if (!ctx.hasUI) return;
    const { done, total, current } = progress(state);
    const label = current ? ` · ${current.text.length > 40 ? `${current.text.slice(0, 39)}…` : current.text}` : '';
    ctx.ui.setStatus('todo', total === 0 || done === total ? undefined : `todo ${done}/${total}${label}`);
  };
  const restore = (ctx: ExtensionContext) => {
    state = stateFromEntries(ctx.sessionManager.getBranch());
    show(ctx);
  };
  pi.on('session_start', async (_event, ctx) => restore(ctx));
  pi.on('session_tree', async (_event, ctx) => restore(ctx));

  pi.registerTool({
    name: 'todo',
    label: 'Todo',
    description: [
      'Keep a task list for multi-step work. One task is in progress while any is pending: `init` starts the first, and `done`, `block` or `remove` of the current task starts the next.',
      'Operations: `init` (items) replaces the list; `add` (items) appends; `start`, `done`, `block` (id, reason), `unblock` and `remove` (id); `view` shows it.',
      'A request that cannot apply fails and leaves the list as it was. The list belongs to the conversation branch, so it survives resuming a session.',
    ].join('\n'),
    promptSnippet: 'todo: a task list for multi-step work (init, add, start, done, block, unblock, remove, view)',
    promptGuidelines: [
      'For work with several steps, `init` a todo list first, mark each task `done` as soon as it is finished, and `view` the list after a context compaction instead of trusting memory.',
    ],
    parameters: Parameters,
    executionMode: 'sequential',
    async execute(_id, params, _signal, _update, ctx) {
      state = applyTodo(state, params);
      show(ctx);
      return { content: [{ type: 'text', text: formatTodos(state) }], details: state };
    },
    renderCall(args, theme) {
      const detail = args.items ? `${args.items.length} task${args.items.length === 1 ? '' : 's'}` : args.id !== undefined ? `#${args.id}` : '';
      return new Text(theme.fg('toolTitle', theme.bold('todo ')) + theme.fg('accent', args.op) + (detail ? theme.fg('muted', ` ${detail}`) : ''), 0, 0);
    },
  });

  pi.registerCommand('todos', {
    description: 'Show the todo list',
    handler: async (_args, ctx) => {
      ctx.ui.notify(formatTodos(state), 'info');
    },
  });
}
