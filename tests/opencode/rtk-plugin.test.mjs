import assert from 'node:assert/strict';
import test from 'node:test';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const pluginDir = resolve(process.argv[2]);
const rtkBin = resolve(process.argv[3]);
const plugin = (await import(pathToFileURL(resolve(pluginDir, 'index.mjs')))).default;

function makeContext() {
  const handlers = {};
  return {
    handlers,
    context: {
      options: { bin: rtkBin },
      shell: {
        hook: async (name, cb) => {
          handlers[name] = cb;
          return { dispose: async () => {} };
        },
      },
    },
  };
}

test('rewrites a command that has an rtk equivalent', async () => {
  const { handlers, context } = makeContext();
  await plugin.setup(context);
  const event = { command: 'git status' };
  await handlers['create.before'](event);
  assert.equal(event.command, 'rtk git status');
});

test('leaves commands already using rtk unchanged', async () => {
  const { handlers, context } = makeContext();
  await plugin.setup(context);
  const event = { command: 'rtk git status' };
  await handlers['create.before'](event);
  assert.equal(event.command, 'rtk git status');
});

test('passes through when RTK_DISABLED is set', async () => {
  const previous = process.env.RTK_DISABLED;
  process.env.RTK_DISABLED = '1';
  try {
    const { handlers, context } = makeContext();
    await plugin.setup(context);
    const event = { command: 'git status' };
    await handlers['create.before'](event);
    assert.equal(event.command, 'git status');
  } finally {
    if (previous === undefined) delete process.env.RTK_DISABLED;
    else process.env.RTK_DISABLED = previous;
  }
});

test('passes through an empty command', async () => {
  const { handlers, context } = makeContext();
  await plugin.setup(context);
  const event = { command: '' };
  await handlers['create.before'](event);
  assert.equal(event.command, '');
});

test('passes through a command with no rtk equivalent', async () => {
  const { handlers, context } = makeContext();
  await plugin.setup(context);
  const event = { command: 'zzz-no-such-command-xyz foo' };
  await handlers['create.before'](event);
  assert.equal(event.command, 'zzz-no-such-command-xyz foo');
});

test('passes through when the command is not a string', async () => {
  const { handlers, context } = makeContext();
  await plugin.setup(context);
  const event = { command: 42 };
  await handlers['create.before'](event);
  assert.equal(event.command, 42);
});
