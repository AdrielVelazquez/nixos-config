import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { pathToFileURL } from 'node:url';
import { after, before, test } from 'node:test';
import { createRequire } from 'node:module';
import { getEventListeners } from 'node:events';

let dir, tool, tuiLib, shutdown;
before(async () => {
  dir = await mkdtemp(join(tmpdir(), 'pi-question-'));
  process.env.PI_CODING_AGENT_DIR = dir;
  const sdk = await import(pathToFileURL(`${process.env.PI_TEST_PACKAGE_DIR}/dist/index.js`).href);
  const require = createRequire(`${process.env.PI_TEST_PACKAGE_DIR}/package.json`);
  const { createJiti } = require('jiti');
  const jiti = createJiti(import.meta.url);
  tuiLib = await jiti.import(`${process.env.PI_TEST_PACKAGE_DIR}/node_modules/@earendil-works/pi-tui/dist/index.js`);
  const loaded = await sdk.discoverAndLoadExtensions([resolve('dotfiles/pi/extensions/question.ts')], dir, dir);
  assert.deepEqual(loaded.errors, []);
  shutdown = () => loaded.extensions.flatMap(extension => extension.handlers.get('session_shutdown') ?? []).forEach(handler => handler({}, {}));
  tool = loaded.extensions.flatMap(extension => [...extension.tools.values()]).find(tool => tool.definition.name === 'question')?.definition;
  assert.equal(typeof tool?.execute, 'function');
});
after(async () => { if (dir) await rm(dir, { recursive: true, force: true }); });
const input = (multiple = false) => ({ questions: [{ header: 'Decision', question: 'Which action?', multiple,
  options: [{ label: 'Safe (Recommended)', description: 'No running-system changes' }, { label: 'Other', description: 'Another choice' }] }] });
const CARD_BG = '\x1b[48;2;30;33;36m';
const theme = { fg: (_token, text) => text, bg: (_token, text) => text, bold: text => text, getBgAnsi: () => CARD_BG, getFgAnsi: () => '\x1b[38;2;255;255;255m' };
function interactive(params = input(), signal = new AbortController().signal) {
  let component, customOptions, customCalls = 0, finished = false;
  const tui = { terminal: { rows: 32, columns: 80 }, requestRender() {} };
  const promise = tool.execute('test-question', params, signal, undefined, {
    hasUI: true, mode: 'tui', ui: {
      select: () => assert.fail('TUI must not use a selector dialog'),
      input: () => assert.fail('custom input must remain on the same card'),
      custom: (factory, options) => {
        customCalls++; customOptions = options;
        return new Promise(resolve => {
          component = factory(tui, theme, { matches: () => false }, result => { finished = true; resolve(result); });
          component.focused = true;
        }).finally(() => component?.dispose?.());
      },
    },
  });
  return { promise, tui, key: data => component.handleInput(data), render: width => component.render(width),
    get component() { return component; }, get finished() { return finished; },
    get customCalls() { return customCalls; }, get customOptions() { return customOptions; } };
}
async function rpc(choose, text = 'custom', multiple = false, signal = new AbortController().signal, params = input(multiple)) {
  const calls = [];
  const result = await tool.execute('test-question', params, signal, undefined,
    { hasUI: true, mode: 'rpc', ui: { select: async (question, options, opts) => { calls.push({ question, options, opts }); return choose(options, calls.length); }, input: async (_title, _placeholder, opts) => { assert.equal(opts.signal, calls.at(-1).opts.signal); return text; } } });
  return { result, calls };
}
test('TUI opens one native in-flow custom prompt with an always-visible editor and explicit submission', async () => {
  const h = interactive();
  assert.equal(h.customCalls, 1);
  assert.notEqual(h.customOptions?.overlay, true);
  const rows = h.render(80).join('\n');
  assert.match(rows, /Question.*Decision/);
  assert.match(rows, /Which action\?/);
  assert.match(rows, /1\..*Safe.*Recommended/);
  assert.match(rows, /Your answer/);
  assert.match(rows, /Enter.*submit|Enter.*Next/);
  assert.equal(h.finished, false, 'initial highlight is not permission');
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['Safe (Recommended)']);
});
test('typing, Unicode, cursor movement, paste and Shift+Enter stay beside the choices', async () => {
  const h = interactive();
  h.key('\t');
  h.key('a界'); h.key('\x1b[D'); h.key('é');
  h.key('\x1b[13;2u');
  h.key('\x1b[200~pasted\ntext\x1b[201~');
  const rows = h.render(50).join('\n');
  assert.match(rows, /Safe/); assert.match(rows, /Other/); assert.match(rows, /Your answer/);
  assert.ok(rows.includes(tuiLib.CURSOR_MARKER), 'focus reaches the native Editor cursor');
  assert.equal(h.finished, false);
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['aé\npasted\ntext界']);
});
test('typing from choices focuses custom input, while focusing alone never submits a choice', async () => {
  const h = interactive();
  h.key('custom');
  h.key('\t'); h.key('\t');
  assert.equal(h.finished, false);
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['custom']);
});
test('multi-select uses Space to toggle and Enter to explicitly submit choices plus custom text', async () => {
  const h = interactive(input(true));
  h.key(' '); h.key('\x1b[B'); h.key(' '); h.key(' ');
  h.key('\t'); h.key('also this');
  assert.match(h.render(80).join('\n'), /Space.*toggle/);
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['Safe (Recommended)', 'also this']);
  const empty = interactive(input(true)); empty.key('\r');
  assert.equal(empty.finished, false, 'Enter does not invent unchecked selections');
  empty.key('\x1b'); await empty.promise;
});
test('batch Back/Next preserves native editor drafts and only the last submit commits the batch', async () => {
  const params = input(); params.questions.push({ ...input().questions[0], header: 'Second', question: 'Then what?' });
  const h = interactive(params);
  h.key('\t'); h.key('first draft'); h.key('\r');
  assert.equal(h.finished, false); assert.match(h.render(80).join('\n'), /2 of 2/);
  h.key('\t'); h.key('second draft');
  h.key('\t'); h.key('\r'); // Back button
  assert.match(h.render(80).join('\n'), /first draft/);
  h.key('\r'); // Next button remains focused
  assert.match(h.render(80).join('\n'), /second draft/);
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers.map(a => a.answer), [['first draft'], ['second draft']]);
});
test('Escape and signal abort cancel the whole unsubmitted batch without granting permission', async () => {
  for (const abort of [false, true]) {
    const controller = new AbortController();
    const params = input(); params.questions.push({ ...input().questions[0], question: 'Next?' });
    const h = interactive(params, controller.signal);
    h.key('\r');
    if (abort) controller.abort(); else h.key('\x1b');
    const result = await h.promise;
    assert.ok(result.details.answers.every(a => a.cancelled && a.answer.length === 0));
    h.key('\r'); // late keys cannot submit after cancellation
  }
  const controller = new AbortController(); controller.abort();
  const h = interactive(input(), controller.signal);
  assert.equal(h.customCalls, 0, 'already aborted calls do not open a prompt');
  assert.equal((await h.promise).details.answers[0].cancelled, true);
});
test('rendering wraps and scrolls choices, keeps input/help visible and respects terminal bounds', async () => {
  const params = input();
  params.questions[0].options = Array.from({ length: 20 }, (_, i) => ({ label: `Choice ${i} 界`, description: 'long wrapped description '.repeat(8) }));
  const h = interactive(params);
  for (const width of [1, 8, 24, 50, 90]) {
    h.tui.terminal.rows = 18;
    const rows = h.render(width);
    assert.ok(rows.every(row => tuiLib.visibleWidth(row) <= width), `fits ${width} columns`);
    assert.ok(rows.length <= 17, `fits short screen at ${width}: ${rows.length}`);
  }
  for (let i = 0; i < 19; i++) h.key('\x1b[B');
  const rows = h.render(50).join('\n');
  assert.match(rows, /20\..*Choice 19/); assert.match(rows, /Your answer/); assert.match(rows, /Esc/);
  h.key('\x1b'); await h.promise;
});
test('RPC keeps supported blocking selection and custom input with abort options', async () => {
  const { result, calls } = await rpc(options => options[0]);
  assert.deepEqual(result.details.answers[0].answer, ['Safe (Recommended)']);
  assert.match(calls[0].options[0], /Safe \(Recommended\)/);
  assert.ok(calls[0].opts.signal);
  const multi = await rpc((options, index) => index <= 2 ? options[index - 1] : 'Done', '', true);
  assert.deepEqual(multi.result.details.answers[0].answer, ['Safe (Recommended)', 'Other']);
  assert.deepEqual((await rpc(() => 'Type your own answer')).result.details.answers[0].answer, ['custom']);
  const cancel = await rpc(() => undefined);
  assert.equal(cancel.result.details.answers[0].cancelled, true);
  assert.deepEqual(cancel.result.details.answers[0].answer, []);
});
test('RPC abort after a pending choice cancels and never asks later questions', async () => {
  const controller = new AbortController();
  const params = input(); params.questions.push(input().questions[0]);
  const { result, calls } = await rpc(options => { controller.abort(); return options[0]; }, '', false, controller.signal, params);
  assert.equal(calls.length, 1);
  assert.ok(result.details.answers.every(a => a.cancelled && a.answer.length === 0));
});
test('question fails clearly rather than hanging in a client without UI', async () => {
  await assert.rejects(tool.execute('test-question', input(), new AbortController().signal, undefined,
    { hasUI: false, mode: 'print' }), /interactive Pi|UI support/);
});
test('self-owned transcript renderers show human Q/A or explicit cancellation, never raw JSON', async () => {
  assert.equal(tool.renderShell, 'self'); assert.equal(tool.exposure, 'model-only');
  const plain = component => component.render(80).join('\n');
  const call = plain(tool.renderCall(input(), theme, { state: {} }));
  assert.match(call, /Question.*Decision/); assert.ok(!call.includes('Which action?'), 'the question body is rendered once with its answer'); assert.ok(!call.includes('"questions"'));
  const partial = plain(tool.renderCall({ questions: [{}, null] }, theme, { state: {} }));
  assert.match(partial, /Question/); assert.ok(!partial.includes('undefined'));
  const result = (await rpc(options => options[0])).result;
  const answer = plain(tool.renderResult(result, { expanded: false }, theme, { state: {} }));
  assert.match(answer, /Which action/); assert.match(answer, /Safe/); assert.ok(!answer.includes('"answers"'));
  const cancelled = (await rpc(() => undefined)).result;
  assert.match(plain(tool.renderResult(cancelled, {}, theme, { state: {} })), /cancelled.*[Nn]o answer|[Nn]o answer.*permission/s);
  const error = plain(tool.renderResult({ content: [{ type: 'text', text: '{"private":"payload"}' }] }, {}, theme, { isError: true, state: {} }));
  assert.match(error, /Question failed/); assert.ok(!error.includes('payload'));
});

test('native encoded printable keys and chunked paste focus and edit the persistent answer', async () => {
  const h = interactive();
  h.key('\x1b[120u');
  assert.ok(h.render(80).join('\n').includes(tuiLib.CURSOR_MARKER));
  h.key('\x1b[200~part'); h.key('\t'); h.key('two'); h.key('\x1b[201~');
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['xpart    two']);
});
test('long choice descriptions can be paged without losing the editor and help', async () => {
  const params = input(); params.questions[0].options = [{ label: 'Long choice', description: 'description '.repeat(100) + 'TAIL WITNESS' }];
  const h = interactive(params); h.tui.terminal.rows = 18;
  h.render(50);
  for (let i = 0; i < 20; i++) { h.key('\x1b[6~'); h.render(50); }
  const rows = h.render(50).join('\n');
  assert.match(rows, /TAIL WITNESS/); assert.match(rows, /Your answer/); assert.match(rows, /Esc/);
  h.key('\x1b'); await h.promise;
});
test('shutdown cancels native prompts and all completion paths remove abort listeners', async () => {
  for (const finish of ['submit', 'cancel', 'shutdown']) {
    const controller = new AbortController();
    const h = interactive(input(), controller.signal);
    assert.equal(getEventListeners(controller.signal, 'abort').length, 1);
    if (finish === 'shutdown') shutdown(); else h.key(finish === 'submit' ? '\r' : '\x1b');
    const result = await h.promise;
    assert.equal(Boolean(result.details.answers[0].cancelled), finish !== 'submit');
    assert.equal(getEventListeners(controller.signal, 'abort').length, 0);
  }
});

test('long question text remains readable by paging while answer input stays present', async () => {
  const params = input(); params.questions[0].question = 'A long question '.repeat(40) + 'QUESTION TAIL';
  const h = interactive(params); h.tui.terminal.rows = 18;
  let seen = '';
  for (let i = 0; i < 20; i++) { seen += h.render(50).join('\n'); h.key('\x1b[6~'); }
  assert.match(seen, /QUESTION TAIL/);
  assert.match(h.render(50).join('\n'), /Your answer/);
  h.key('\x1b'); await h.promise;
});

test('clicking the persistent editor forwards native cursor placement without submitting', async () => {
  const h = interactive();
  h.key('ab界cd');
  const rows = h.render(50);
  const label = rows.findIndex(row => row.includes('Your answer'));
  const mouse = { type: 'click', button: 'left', x: 4, y: label + 1, screenX: 4, screenY: label + 1, width: 50, height: rows.length, shift: false, alt: false, ctrl: false };
  h.key('\t'); h.key('\t');
  assert.equal(h.component.handleMouse(mouse).focus, true);
  h.key('X');
  assert.equal(h.finished, false);
  assert.match(h.render(50).join('\n'), /Safe/);
  h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['abX界cd']);
});
test('choice clicks toggle multi-selections but require explicit Enter to submit', async () => {
  const h = interactive(input(true)); const rows = h.render(60);
  const y = rows.findIndex(row => row.includes('2. Other'));
  h.component.handleMouse({ type: 'click', button: 'left', x: 5, y, screenX: 5, screenY: y, width: 60, height: rows.length, shift: false, alt: false, ctrl: false });
  assert.equal(h.finished, false); h.key('\r');
  assert.deepEqual((await h.promise).details.answers[0].answer, ['Other']);
});

test('a single preset chosen after typing wins over the preserved custom draft', async () => {
  for (const method of ['mouse', 'keyboard']) {
    const h = interactive();
    try {
      h.key('not the final answer');
      if (method === 'mouse') {
        const rows = h.render(80);
        const y = rows.findIndex(row => row.includes('2. Other'));
        h.component.handleMouse({ type: 'click', button: 'left', x: 5, y, width: 80, height: rows.length, shift: false, alt: false, ctrl: false });
      } else { h.key('\t'); h.key('\t'); h.key('2'); }
      h.key('\r');
      assert.deepEqual((await h.promise).details.answers[0].answer, ['Other'], method);
    } finally { if (!h.finished) h.key('\x1b'); await h.promise; }
  }
});

test('rendered Next, Back and Submit actions are clickable and preserve batch drafts', async () => {
  const params = input(); params.questions.push({ ...input().questions[0], header: 'Second', question: 'Then what?' });
  const h = interactive(params);
  const click = name => {
    const rows = h.render(80);
    const y = rows.findIndex(row => row.includes('[' + name + ']') || row.includes('[> ' + name + ']'));
    assert.ok(y >= 0, name + ' is visible');
    const x = rows[y].replace(/\x1b\[[0-9;]*m/g, '').indexOf(name) + 1;
    const result = h.component.handleMouse({ type: 'click', button: 'left', x, y, width: 80, height: rows.length, shift: false, alt: false, ctrl: false });
    if (h.finished) assert.notEqual(result?.focus, true, 'a closed card must not reclaim keyboard focus from the restored prompt');
  };
  try {
    h.key('first draft'); click('Next');
    assert.match(h.render(80).join('\n'), /2 of 2/);
    h.key('second draft'); click('Back');
    assert.match(h.render(80).join('\n'), /first draft/);
    click('Next');
    assert.match(h.render(80).join('\n'), /second draft/);
    click('Submit answer');
    assert.equal(h.finished, true);
    assert.deepEqual((await h.promise).details.answers.map(a => a.answer), [['first draft'], ['second draft']]);
  } finally { if (!h.finished) h.key('\x1b'); await h.promise; }
});

test('the question card has a filled background and bounds text on wide terminals', async () => {
  const params = input(); params.questions[0].options[0].description = 'readable description '.repeat(20);
  const h = interactive(params);
  try {
    const rows = h.render(240);
    assert.ok(rows.every(row => row.includes(CARD_BG) && tuiLib.visibleWidth(row) === 240));
    const plain = rows.map(row => row.replace(/\x1b\[[0-9;]*m/g, '').trimEnd());
    assert.ok(plain.every(row => tuiLib.visibleWidth(row) <= 102), 'text stays in a readable column while the card fills its region');
  } finally { h.key('\x1b'); await h.promise; }
});

test('very short question cards keep the input cursor and cancellation help visible', async () => {
  const h = interactive(); h.tui.terminal.rows = 8; h.key('typed');
  try {
    const rows = h.render(60);
    assert.ok(rows.length <= 5, 'card reserves the footer and transcript rows');
    assert.ok(rows.join('\n').includes(tuiLib.CURSOR_MARKER), 'the focused native editor cursor is not clipped');
    assert.match(rows.join('\n'), /Esc/);
  } finally { h.key('\x1b'); await h.promise; }
});
