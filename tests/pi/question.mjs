import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { after, before, test } from 'node:test';

let dir, tool;
before(async () => {
  dir = await mkdtemp(join(tmpdir(), 'pi-question-'));
  const sdk = await import(pathToFileURL(`${process.env.PI_TEST_PACKAGE_DIR}/dist/index.js`).href);
  const loaded = await sdk.discoverAndLoadExtensions([resolve('dotfiles/pi/extensions/question.ts')], dir, dir);
  assert.deepEqual(loaded.errors, []);
  tool = loaded.extensions.flatMap(extension => [...extension.tools.values()]).find(tool => tool.definition.name === 'question')?.definition;
  assert.equal(typeof tool?.execute, 'function');
});
after(async () => { if (dir) await rm(dir, { recursive: true, force: true }); });
const input = (multiple = false) => ({ questions: [{ header: 'Decision', question: 'Which action?', multiple,
  options: [{ label: 'Safe (Recommended)', description: 'No running-system changes' }, { label: 'Other', description: 'Another choice' }] }] });
async function run(choose, text = 'custom', multiple = false) {
  const calls = [];
  const result = await tool.execute('test-question', input(multiple), new AbortController().signal, undefined,
    { hasUI: true, mode: 'tui', ui: { select: async (question, options) => { calls.push({ question, options }); return choose(options, calls.length); }, input: async () => text } });
  return { result, calls };
}
test('question uses blocking native selection with recommended option first', async () => {
  const { result, calls } = await run(options => options[0]);
  assert.deepEqual(result.details.answers[0].answer, ['Safe (Recommended)']);
  assert.match(calls[0].options[0], /Safe \(Recommended\)/);
});
test('question supports multiple selections and a free-form response', async () => {
  const multi = await run((options, index) => index <= 2 ? options[index - 1] : 'Done', '', true);
  assert.deepEqual(multi.result.details.answers[0].answer, ['Safe (Recommended)', 'Other']);
  const custom = await run(() => 'Type your own answer');
  assert.deepEqual(custom.result.details.answers[0].answer, ['custom']);
});
test('question records cancellation without inventing permission', async () => {
  const { result } = await run(() => undefined);
  assert.equal(result.details.answers[0].cancelled, true);
  assert.deepEqual(result.details.answers[0].answer, []);
});
test('question fails clearly rather than hanging in a client without UI', async () => {
  await assert.rejects(tool.execute('test-question', input(), new AbortController().signal, undefined,
    { hasUI: false, mode: 'print' }), /interactive Pi|UI support/);
});
