import test from 'node:test';
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { join } from 'node:path';

const root = process.env.PI_TEST_PACKAGE_DIR;
assert.ok(root, 'PI_TEST_PACKAGE_DIR must name the real Pi installation');
const requirePi = createRequire(join(root, 'package.json'));
const aliases = Object.fromEntries(['pi-coding-agent', 'pi-ai', 'pi-tui'].map(name => [
  `@earendil-works/${name}`, name === 'pi-coding-agent' ? join(root, 'dist/index.js') : join(root, 'node_modules/@earendil-works', name, 'dist/index.js'),
]));
aliases.typebox = requirePi.resolve('typebox');
const jiti = requirePi('jiti').createJiti(import.meta.url, { alias: aliases });
const { createTodo } = await jiti.import('../../dotfiles/pi/extensions/todo.ts');
const { visibleWidth } = await import(aliases['@earendil-works/pi-tui']);

function fixture(options = {}) {
  const handlers = new Map(), commands = new Map(), shortcuts = new Map();
  let tool, current;
  const theme = { fg: (_color, text) => text, bold: text => text };
  const pi = {
    on: (name, handler) => { if (!handlers.has(name)) handlers.set(name, []); handlers.get(name).push(handler); },
    registerTool: value => { tool = value; },
    registerCommand: (name, value) => commands.set(name, value),
    registerShortcut: (key, value) => shortcuts.set(key, value),
    appendEntry: (customType, data) => current.entries.push({ type: 'custom', customType, data: structuredClone(data) }),
  };
  createTodo(pi, options);
  const context = (id, mode = 'tui') => {
    const ctx = { entries: [], mode, hasUI: mode !== 'json', widgets: new Map(), statuses: new Map(), notices: [], expanded: false, stale: false, renders: 0,
      sessionManager: { getSessionId: () => id, getBranch: () => ctx.entries } };
    ctx.ui = {
      get theme() { if (ctx.stale) throw new Error('stale context'); return theme; },
      getToolsExpanded: () => ctx.expanded,
      setStatus: (key, text) => ctx.statuses.set(key, text),
      notify: text => ctx.notices.push(text),
      setWidget: (key, value) => {
        if (ctx.stale) throw new Error('stale context');
        if (value === undefined) ctx.widgets.delete(key);
        else ctx.widgets.set(key, value({ requestRender: () => ctx.renders++ }, theme));
      },
    };
    return ctx;
  };
  const emit = async (name, ctx) => { current = ctx; for (const handler of handlers.get(name) ?? []) await handler({ type: name }, ctx); };
  const execute = async (ctx, args) => { current = ctx; return tool.execute('call', args, undefined, undefined, ctx); };
  const lines = (ctx, width = 100) => [...ctx.widgets.values()].flatMap(widget => widget.render(width));
  return { handlers, commands, shortcuts, context, emit, execute, lines, get tool() { return tool; } };
}

test('nested mutations append snapshots; reads and failures never append or change state', async () => {
  const f = fixture(), ctx = f.context('root', 'json');
  await f.emit('session_start', ctx);
  const first = await f.execute(ctx, { op: 'init', items: ['One', 'Two'] });
  assert.equal(ctx.entries.length, 1);
  assert.equal(ctx.entries[0].customType, 'pi-todo-state');
  assert.equal(ctx.entries[0].data.version, 1);
  assert.deepEqual(ctx.entries[0].data.state, first.details);
  const view = await f.execute(ctx, { op: 'view', status: 'pending' });
  assert.equal(view.details.todos.length, 2);
  assert.equal(ctx.entries.length, 1);
  await assert.rejects(f.execute(ctx, { op: 'done', id: 99 }), /exist/);
  assert.equal(ctx.entries.length, 1);
  assert.equal((await f.execute(ctx, { op: 'view' })).details.todos[0].status, 'in_progress');
});

test('session stores, ownership and shutdown cannot clobber or repaint siblings', async () => {
  const f = fixture(), parent = f.context('parent'), child = f.context('child');
  await f.emit('session_start', parent);
  await f.execute(parent, { op: 'init', items: ['Parent task'] });
  const parentView = f.lines(parent).join('\n');
  await f.emit('session_start', child);
  await f.execute(child, { op: 'init', items: ['Child task'] });
  assert.equal(child.widgets.size, 0);
  assert.equal(f.lines(parent).join('\n'), parentView);
  assert.equal((await f.execute(child, { op: 'view' })).details.todos[0].text, 'Child task');
  await f.emit('session_shutdown', child);
  child.stale = true;
  assert.match(f.lines(parent).join('\n'), /Parent task/);
  const widget = [...parent.widgets.values()][0];
  await f.emit('session_shutdown', parent);
  parent.stale = true;
  assert.deepEqual(widget.render(80), []);
});

test('tree, compact and fresh session events restore only their own branch snapshots', async () => {
  const f = fixture(), ctx = f.context('session');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: ['One', 'Two'] });
  const firstBranch = structuredClone(ctx.entries);
  await f.execute(ctx, { op: 'done', id: 1 });
  ctx.entries = firstBranch;
  await f.emit('session_tree', ctx);
  assert.equal((await f.execute(ctx, { op: 'view' })).details.todos[0].status, 'in_progress');
  await f.emit('session_compact', ctx);
  assert.equal((await f.execute(ctx, { op: 'view' })).details.todos.length, 2);
  await f.emit('session_shutdown', ctx);
  const fresh = f.context('fresh');
  await f.emit('session_start', fresh);
  assert.equal((await f.execute(fresh, { op: 'view' })).details.todos.length, 0);
});

test('collapsed widgets have a localized hint and native expansion reveals every task', async () => {
  const f = fixture({ maxWidgetLines: 5 }), ctx = f.context('root');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: Array.from({ length: 12 }, (_, i) => `Task ${i + 1}`) });
  await f.execute(ctx, { op: 'start', id: 12 });
  assert(f.lines(ctx).some(row => row.includes('Task 12')));
  assert(f.lines(ctx).length <= 6);
  await f.shortcuts.get('ctrl+shift+t').handler(ctx);
  assert(f.lines(ctx).some(row => row.includes('ctrl+shift+t')));
  assert.equal(f.lines(ctx).some(row => row.includes('Task 12')), false);
  ctx.expanded = true;
  assert.equal(f.lines(ctx).filter(row => /Task \d+/.test(row)).length, 12);
  ctx.expanded = false;
  await f.shortcuts.get('ctrl+shift+t').handler(ctx);
  assert(f.lines(ctx).some(row => row.includes('Task 12')));
});

test('UI locale does not translate task text or model-facing results', async () => {
  for (const locale of ['en', 'de', 'es', 'fr', 'pt', 'pt-BR', 'ru', 'uk', 'zh']) {
    const f = fixture({ locale }), ctx = f.context(locale);
    await f.emit('session_start', ctx);
    const reply = await f.execute(ctx, { op: 'init', items: ['literal task'] });
    assert.match(reply.content[0].text, /^Todos:/);
    assert.match(f.lines(ctx).join('\n'), /literal task/);
    await f.commands.get('todos').handler('', ctx);
    assert.match(ctx.notices.at(-1), /literal task/);
    if (locale === 'fr') {
      assert.match(f.lines(ctx)[0], /Tâches/);
      assert.match(ctx.notices.at(-1), /Tâches/);
    }
  }
});

test('widget rows fit narrow terminals and do not contain task-controlled escape sequences', async () => {
  const f = fixture(), ctx = f.context('root');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: ['中文 long task \x1b[31mred\x1b[0m\nnext', 'Other'] });
  for (const width of [1, 2, 8, 20, 80]) {
    const lines = f.lines(ctx, width);
    assert(lines.every(row => visibleWidth(row) <= width));
    assert(lines.every(row => !/[\x00-\x1f\x7f]/.test(row.replace(/\x1b\[0m/g, ''))), JSON.stringify({ width, lines }));
  }
});

test('completed hiding is optional and cannot hide a reopened task', async () => {
  const f = fixture({ hideCompleted: true }), ctx = f.context('root');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: ['First', 'Second'] });
  await f.execute(ctx, { op: 'done', id: 1 });
  assert.match(f.lines(ctx).join('\n'), /First/);
  await f.emit('agent_start', ctx);
  assert.doesNotMatch(f.lines(ctx).join('\n'), /First/);
  await f.execute(ctx, { op: 'start', id: 1 });
  assert.match(f.lines(ctx).join('\n'), /First/);
});

test('slash filters preserve canonical state; RPC uses a composable status', async () => {
  const f = fixture(), ctx = f.context('root', 'rpc');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: [{ text: 'One', owner: 'Ada' }, { text: 'Two', owner: 'Lin' }] });
  await f.commands.get('todos').handler('pending owner=Lin Two', ctx);
  assert.match(ctx.notices.at(-1), /Two/);
  assert.doesNotMatch(ctx.notices.at(-1), /One/);
  assert.equal((await f.execute(ctx, { op: 'view' })).details.todos.length, 2);
  assert.match(ctx.statuses.get('todo'), /0\/2/);
  assert.equal(ctx.widgets.size, 0);
});

test('disabled collapse shortcut and invalid options never hijack arbitrary keys', () => {
  assert.equal(fixture({ collapseKey: null }).shortcuts.size, 0);
  for (const key of ['ctrl++', 'shift+?', 'alt+[', 'ctrl+esc', 'super+f12']) {
    assert(fixture({ collapseKey: key }).shortcuts.has(key));
  }
  assert.throws(() => fixture({ collapseKey: 'ctr+]' }), /shortcut|key/i);
  assert.throws(() => fixture({ maxWidgetLines: 2 }), /maxWidgetLines/);
  assert.throws(() => fixture({ maxWidgetLines: 7.5 }), /maxWidgetLines/);
});

test('clearing an owner succeeds and its mutation reply contains the entire list', async () => {
  const f = fixture(), ctx = f.context('root', 'json');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: [{ text: 'Owned', owner: 'Ada' }, 'Other'] });
  const reply = await f.execute(ctx, { op: 'update', id: 1, owner: null });
  assert.equal(reply.details.todos[0].owner, undefined);
  assert.match(reply.content[0].text, /Owned[\s\S]*Other/);
  assert.equal(ctx.entries.length, 2);
  await f.emit('session_compact', ctx);
  assert.equal((await f.execute(ctx, { op: 'get', id: 1 })).details.todos[0].owner, undefined);
});

test('native expansion reveals rows hidden by completion hiding', async () => {
  const f = fixture({ hideCompleted: true }), ctx = f.context('root');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: ['First', 'Second'] });
  await f.execute(ctx, { op: 'done', id: 1 });
  await f.emit('agent_start', ctx);
  assert.doesNotMatch(f.lines(ctx).join('\n'), /First/);
  ctx.expanded = true;
  assert.match(f.lines(ctx).join('\n'), /First/);
});

test('recompleted tasks stay visible until the next run', async () => {
  const f = fixture({ hideCompleted: true }), ctx = f.context('root');
  await f.emit('session_start', ctx);
  await f.execute(ctx, { op: 'init', items: ['First', 'Second'] });
  await f.execute(ctx, { op: 'done', id: 1 });
  await f.emit('agent_start', ctx);
  await f.execute(ctx, { op: 'start', id: 1 });
  await f.execute(ctx, { op: 'done', id: 1 });
  assert.match(f.lines(ctx).join('\n'), /First/);
  await f.emit('agent_start', ctx);
  assert.doesNotMatch(f.lines(ctx).join('\n'), /First/);
});
