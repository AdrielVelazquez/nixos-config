import assert from 'node:assert/strict';
import { test } from 'node:test';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
const sdk = process.env.PI_TEST_PACKAGE_DIR;
const require = createRequire(`${sdk}/package.json`);
const { createJiti } = require('jiti');
const jiti = createJiti(import.meta.url, { alias: {
  '@earendil-works/pi-coding-agent': `${sdk}/dist/index.js`,
  '@earendil-works/pi-tui': `${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`,
} });
const { CustomEditor } = await jiti.import(`${sdk}/dist/index.js`);
const { Markdown } = await jiti.import(`${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`);
const { default: install } = await jiti.import(resolve('dotfiles/pi/extensions/neutral-foreground.ts'));
const neutral = '\x1b[38;2;201;198;188m';
function api() {
  const events = new Map();
  const pi = { on(name, handler) { events.set(name, handler); } };
  const ctx = { mode: 'tui', ui: { theme: { fg: (_token, text) => neutral + text + '\x1b[39m' } } };
  install(pi);
  return { start: () => events.get('session_start')({}, ctx), stop: () => events.get('session_shutdown')({}, ctx), ctx };
}
test('neutral foreground preserves explicit colors, reopens resets, reads live theme and restores prototypes', () => {
  const originals = [Markdown.prototype.render, CustomEditor.prototype.render];
  const line = 'plain\x1b[31mred\x1b[39mplain\x1b[0mend\x1b[0;32mgreen\x1b[48;2;0;0;0mstill green';
  const render = function () { return [line]; };
  Markdown.prototype.render = render; CustomEditor.prototype.render = render;
  try {
    const a = api(); a.start();
    const wrapped = Markdown.prototype.render;
    const b = api(); b.start();
    assert.equal(Markdown.prototype.render, wrapped, 'two factories must not double-wrap');
    for (const prototype of [Markdown.prototype, CustomEditor.prototype]) {
      const result = prototype.render.call({}, 80)[0];
      assert.equal(result, neutral + 'plain\x1b[31mred\x1b[39m' + neutral + 'plain\x1b[0m' + neutral + 'end\x1b[0;32mgreen\x1b[48;2;0;0;0mstill green\x1b[39m');
    }
    b.ctx.ui.theme = { fg: (_token, text) => '\x1b[37m' + text + '\x1b[39m' };
    assert.ok(Markdown.prototype.render.call({}, 80)[0].startsWith('\x1b[37m'));
    a.stop();
    assert.equal(Markdown.prototype.render, wrapped, 'one owner remains');
    b.stop();
    assert.equal(Markdown.prototype.render, render);
    assert.equal(CustomEditor.prototype.render, render);
  } finally { [Markdown.prototype.render, CustomEditor.prototype.render] = originals; }
});
test('headless sessions do not patch rendering and missing host methods are ignored', () => {
  const markdown = Markdown.prototype.render, editor = CustomEditor.prototype.render;
  const f = api(); f.ctx.mode = 'json'; f.start();
  assert.equal(Markdown.prototype.render, markdown); assert.equal(CustomEditor.prototype.render, editor); f.stop();
  try {
    Markdown.prototype.render = undefined; CustomEditor.prototype.render = undefined;
    const g = api(); g.start(); g.stop();
    assert.equal(Markdown.prototype.render, undefined); assert.equal(CustomEditor.prototype.render, undefined);
  } finally { Markdown.prototype.render = markdown; CustomEditor.prototype.render = editor; }
});
