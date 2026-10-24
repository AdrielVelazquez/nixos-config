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
const core = await jiti.import(resolve('dotfiles/pi/extensions/opencode-ui-core.ts'));
const { default: install } = await jiti.import(resolve('dotfiles/pi/extensions/opencode-ui.ts'));
const host = await jiti.import(`${sdk}/dist/index.js`);
const { visibleWidth, rgbColor } = await jiti.import(`${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`);

const BG = '\x1b[48;2;20;20;20m';
const widths = (lines) => lines.map((line) => visibleWidth(line));

test('paint fills to width, keeps the background through nested resets and truncates overflow', () => {
  const painted = core.paint('a\x1b[0mb\x1b[39mc\x1b[0;32md', 10, BG);
  assert.equal(visibleWidth(painted), 10);
  assert.ok(painted.startsWith(BG));
  assert.ok(painted.includes('\x1b[0m' + BG), 'a full reset reopens the fill');
  assert.ok(painted.includes('\x1b[0;32m' + BG), 'a reset that also sets a colour reopens the fill');
  assert.ok(!painted.includes('\x1b[39m' + BG), 'a foreground-only reset keeps the fill and needs no reopening');
  assert.equal(visibleWidth(core.paint('x'.repeat(30), 12, BG)), 12);
  assert.equal(core.paint('x', 0, BG), '');
});

test('keepBackground leaves a sequence that sets a new background alone', () => {
  assert.equal(core.keepBackground('\x1b[0;48;2;1;2;3mx', BG), '\x1b[0;48;2;1;2;3mx');
  assert.equal(core.keepBackground('\x1b[49mx', BG), '\x1b[49m' + BG + 'x');
});

test('parseDiff reads Pi diff output including gaps; diffBlock paints every row to width', () => {
  const rows = core.parseDiff([' 1 const a = 1;', '-2 return exp < now;', '+2 return exp <= now;', '  ...', ' 9 }'].join('\n'));
  assert.deepEqual(rows.map((row) => row.kind), ['ctx', 'del', 'add', 'gap', 'ctx']);
  assert.equal(rows[2].text, 'return exp <= now;');
  const style = { fg: (_token, text) => text, bgs: { ctx: BG, add: '\x1b[48;2;0;40;0m', del: '\x1b[48;2;40;0;0m' } };
  const block = core.diffBlock(rows, 60, style, 18);
  assert.equal(block.length, rows.length + 2, 'padding rows above and below');
  assert.ok(widths(block).every((w) => w === 60));
  assert.ok(block.some((line) => line.includes(style.bgs.add)) && block.some((line) => line.includes(style.bgs.del)));
  assert.equal(core.diffBlock(rows, 60, style, 2).length, 4, 'row cap applies before padding');
  assert.deepEqual(core.diffBlock([], 60, style, 18), []);
});

test('splitShellFailure separates the exit sentence from the output', () => {
  assert.deepEqual(core.splitShellFailure('boom\n\nCommand exited with code 2'), { output: 'boom', failure: 'exit 2' });
  assert.equal(core.splitShellFailure('Command timed out after 5s').failure, 'Command timed out after 5s');
  assert.deepEqual(core.splitShellFailure('fine\n'), { output: 'fine' });
});

test('shellBlock keeps the output tail when collapsed and everything when expanded', () => {
  const style = { bg: BG, fg: (_token, text) => text };
  const output = Array.from({ length: 30 }, (_, i) => `line ${i + 1}`).join('\n');
  const base = { command: 'seq 30', output, maxLines: 5, pending: false, hint: 'ctrl+o to expand' };
  const collapsed = core.shellBlock({ ...base, expanded: false }, 60, style);
  const expanded = core.shellBlock({ ...base, expanded: true }, 60, style);
  const text = (lines) => lines.map((line) => line.replace(/\x1b\[[0-9;]*m/g, '').trimEnd()).join('\n');
  assert.ok(text(collapsed).includes('… 25 earlier lines · ctrl+o to expand'));
  assert.ok(text(collapsed).includes('line 30') && !text(collapsed).includes('line 1\n'));
  assert.ok(text(expanded).includes('line 1\n') && !text(expanded).includes('earlier line'));
  assert.ok(widths([...collapsed, ...expanded]).every((w) => w === 60), 'every row fills the block width');
  const failed = core.shellBlock({ ...base, output: 'x', expanded: false, failure: 'exit 1', duration: 2500 }, 60, style);
  assert.ok(text(failed).includes('exit 1') && text(failed).includes('2.5s'));
  assert.deepEqual(core.shellBlock({ ...base, expanded: false }, 8, style), [], 'too narrow to draw');
});

test('restyleFences swaps fences for a filled block and strips structural indentation, even behind colour prefixes', () => {
  const prefix = '\x1b[38;2;238;238;238m';
  const lines = [prefix + '   prose', prefix + '   ```ts', prefix + '     const a = 1;', prefix + '       nested', prefix + '   ```', prefix + '   after'];
  const out = core.restyleFences(lines, 40, BG, (lang) => `<${lang}>`);
  const plain = out.map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
  assert.equal(plain[1].trimEnd(), '   <ts>', 'label row replaces the opening fence');
  assert.equal(plain[2].trimEnd(), '   const a = 1;', 'code starts in the prose column');
  assert.equal(plain[3].trimEnd(), '     nested', 'code keeps its own indentation');
  assert.equal(plain[4].trim(), '', 'closing fence becomes padding');
  assert.equal(out[0], lines[0]);
  assert.equal(out[5], lines[5]);
  assert.ok(widths(out.slice(1, 5)).every((w) => w === 38), 'block spans the width minus a two column margin each side');
  assert.equal(core.restyleFences(['   ```', '   x', '   ```'], 20, BG, (l) => l).length, 3, 'unlabelled fence still blocks');
});

test('formatting helpers', () => {
  assert.equal(core.formatDuration(420), '420ms');
  assert.equal(core.formatDuration(4210), '4.2s');
  assert.equal(core.formatDuration(72000), '1m 12s');
  assert.equal(core.formatDuration(-1), '');
  assert.equal(core.formatTokens(950), '950');
  assert.equal(core.formatTokens(12400), '12K');
  assert.equal(core.formatTokens(2_300_000), '2.3M');
  assert.equal(core.shortenPath('/home/a/proj/src/x.ts', '/home/a/proj', '/home/a'), 'src/x.ts');
  assert.equal(core.shortenPath('/home/a/other', '/home/a/proj', '/home/a'), '~/other');
  const row = core.spread('left side', 'right', 40);
  assert.equal(visibleWidth(row), 40);
  assert.ok(row.startsWith('left side') && row.endsWith('right'));
  assert.equal(core.spread('a long left side that cannot fit with the right', 'right side here', 20).includes('right side'), false, 'right drops before the left is cut');
});

// --- extension wiring -------------------------------------------------------------------------------------

const theme = {
  getColorMode: () => 'truecolor',
  getBgAnsi: () => BG,
  getFgAnsi: () => '\x1b[38;2;92;156;245m',
  fg: (_token, text) => `\x1b[38;2;1;2;3m${text}\x1b[39m`,
  bold: (text) => text,
  colors: { userMessageBg: rgbColor(20, 20, 20), toolSuccessBg: rgbColor(20, 20, 20), toolDiffAdded: rgbColor(0, 255, 0), toolDiffRemoved: rgbColor(255, 0, 0) },
};

function harness(mode = 'tui') {
  const handlers = new Map();
  let resolver;
  const calls = [];
  const pi = { on: (name, handler) => handlers.set(name, handler), registerToolRenderer: (fn) => { resolver = fn; } };
  const ctx = { mode, cwd: '/proj', sessionManager: { getEntries: () => [], getEntryCount: () => 0, getSessionId: () => 's' }, getContextUsage: () => undefined, ui: { theme, setEditorComponent: (f) => calls.push(['editor', f]), setFooter: (f) => calls.push(['footer', f]), setHeader: (f) => calls.push(['header', f]) } };
  install(pi);
  return { handlers, ctx, calls, resolver: (name, next = () => undefined) => resolver(name, next), start: () => handlers.get('session_start')({}, ctx), stop: () => handlers.get('session_shutdown')({}, ctx) };
}

test('the skin patches the message components in TUI mode only, and restores them on shutdown', () => {
  const protos = [host.UserMessageComponent.prototype, host.AssistantMessageComponent.prototype, host.BashExecutionComponent.prototype];
  const originals = protos.map((p) => p.render);
  const seen = [];
  protos[0].render = function (width) { seen.push(['user', width]); return ['x'.repeat(width)]; };
  protos[1].render = function (width) { seen.push(['assistant', width]); return ['y'.repeat(width)]; };
  protos[2].render = function (width) { seen.push(['shell', width]); return ['', '─'.repeat(width), ' $ echo hi', ' hi', '─'.repeat(width)]; };
  const fakes = protos.map((p) => p.render);
  try {
    const headless = harness('json'); headless.start();
    assert.deepEqual(protos.map((p) => p.render), fakes, 'non-TUI modes leave rendering alone');
    assert.deepEqual(headless.calls, []);
    headless.stop();

    const a = harness(); a.start();
    assert.deepEqual(a.calls.map(([kind]) => kind).sort(), ['editor', 'footer', 'header']);
    const user = protos[0].render.call({}, 40);
    assert.equal(seen.at(-1)[1], 38, 'user content leaves room for the bar and a gap');
    assert.ok(user[0].includes('┃') && visibleWidth(user[0]) === 40);
    const assistant = protos[1].render.call({ lastMessage: undefined }, 40);
    assert.equal(seen.at(-1)[1], 38);
    assert.equal(visibleWidth(assistant[0]), 40, 'assistant content is indented two columns');
    const shell = protos[2].render.call({}, 40).map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
    assert.deepEqual(shell.map((line) => line.trimEnd()), ['', '', '   $ echo hi', '   hi', ''], 'rules are dropped and the command joins the panel');
    assert.ok(widths(protos[2].render.call({}, 40).slice(1)).every((w) => w === 40));
    const wrapped = protos[0].render;
    const b = harness(); b.start();
    assert.equal(protos[0].render, wrapped, 'a second session does not double-wrap');
    a.stop();
    assert.equal(protos[0].render, wrapped, 'the patch stays until the last owner stops');
    b.stop();
    assert.deepEqual(protos.map((p) => p.render), fakes, 'prototypes are restored');
  } finally { protos.forEach((p, i) => { p.render = originals[i]; }); }
});

test('assistant answers end with a model footer only when finished and without tool calls', () => {
  const proto = host.AssistantMessageComponent.prototype, original = proto.render;
  proto.render = () => ['reply'];
  try {
    const h = harness(); h.ctx.model = { id: 'm' }; h.start();
    const message = { stopReason: 'stop', provider: 'p', model: 'claude-x', timestamp: 7 };
    const render = (state) => proto.render.call(state, 60).map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
    h.handlers.get('agent_start')({}, h.ctx);
    h.handlers.get('message_end')({ message: { role: 'assistant', timestamp: 7 } }, h.ctx);
    const finished = render({ lastMessage: message, isStreaming: false, hasToolCalls: false });
    assert.ok(finished.at(-1).includes('▣') && finished.at(-1).includes('claude-x'));
    assert.match(finished.at(-1), /\d+ms|\d+\.\ds/, 'duration comes from the run that produced it');
    assert.equal(render({ lastMessage: message, isStreaming: true, hasToolCalls: false }).length, 1);
    assert.equal(render({ lastMessage: message, isStreaming: false, hasToolCalls: true }).length, 1);
    assert.match(render({ lastMessage: { ...message, stopReason: 'aborted' }, isStreaming: false, hasToolCalls: false }).at(-1), /interrupted/);
    h.stop();
  } finally { proto.render = original; }
});

test('tool renderers: built-ins get inline or block renderers, foreign tools get the panel, self-shell tools are untouched', () => {
  const h = harness(); h.start();
  const ctxFor = (extra = {}) => ({ state: {}, cwd: '/proj', isPartial: false, isError: false, expanded: false, ...extra });
  const text = (component, width = 80) => component.render(width).map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));

  const read = h.resolver('read');
  assert.equal(read.renderShell, 'self');
  const readCtx = ctxFor();
  assert.deepEqual(text(read.renderCall({ path: '/proj/src/a.ts', offset: 5, limit: 10 }, theme, readCtx)).map((l) => l.trim()), ['→ Read src/a.ts [offset=5, limit=10]']);
  assert.deepEqual(text(read.renderResult({ content: [{ type: 'text', text: 'body' }] }, { expanded: false }, theme, readCtx)), [], 'collapsed read shows no body');

  const grep = h.resolver('grep');
  const grepCtx = ctxFor();
  const grepCall = grep.renderCall({ pattern: 'foo', path: 'src' }, theme, grepCtx);
  grep.renderResult({ content: [{ type: 'text', text: 'a:1: foo\nb:2: foo' }] }, { expanded: false }, theme, grepCtx);
  assert.match(text(grepCall)[0], /Grep "foo" in src \(2 matches\)/, 'the call line picks up the result count lazily');

  const ls = h.resolver('ls');
  const lsCtx = ctxFor();
  const lsCall = ls.renderCall({ path: 'src' }, theme, lsCtx);
  ls.renderResult({ content: [{ type: 'text', text: 'a.ts\nb.ts' }] }, { expanded: false }, theme, lsCtx);
  assert.match(text(lsCall)[0], /List src \(2 entries\)/);
  const none = ctxFor();
  const noneCall = grep.renderCall({ pattern: 'zzz' }, theme, none);
  grep.renderResult({ content: [{ type: 'text', text: 'No matches found for zzz.' }] }, { expanded: false }, theme, none);
  assert.match(text(noneCall)[0], /\(0 matches\)/);
  const counted = ctxFor();
  const countedCall = grep.renderCall({ pattern: 'foo' }, theme, counted);
  grep.renderResult({ content: [{ type: 'text', text: 'file\n  1: foo\n  2: foo' }], details: { matches: 2 } }, { expanded: false }, theme, counted);
  assert.match(text(countedCall)[0], /\(2 matches\)/, 'a tool-reported count beats counting printed lines');

  const failing = h.resolver('edit');
  const editCtx = ctxFor({ isError: true });
  const errorRows = text(failing.renderResult({ content: [{ type: 'text', text: 'no match' }] }, { expanded: false }, theme, editCtx));
  assert.ok(errorRows.join('\n').includes('no match'));

  const edit = h.resolver('edit');
  const diffCtx = ctxFor();
  const diff = text(edit.renderResult({ content: [], details: { diff: ' 1 a\n-2 b\n+2 c', warnings: ['careful'] } }, { expanded: false }, theme, diffCtx), 60);
  assert.ok(diff.some((line) => line.includes('- b')) && diff.some((line) => line.includes('+ c')) && diff.some((line) => line.includes('careful')));

  const bash = h.resolver('bash');
  const bashCtx = ctxFor({ isError: true, durationMs: 100 });
  const bashCall = bash.renderCall({ command: 'false' }, theme, bashCtx);
  bash.renderResult({ content: [{ type: 'text', text: 'oops\n\nCommand exited with code 1' }] }, { expanded: false }, theme, bashCtx);
  const block = text(bashCall, 50).map((l) => l.trimEnd());
  assert.ok(block.some((l) => l.includes('$ false')) && block.some((l) => l.includes('oops')) && block.some((l) => l.includes('exit 1')));
  assert.ok(widths(bashCall.render(50)).every((w) => w === 50));

  const native = { renderCall: () => ({ render: () => ['native call'], invalidate() {} }), renderResult: () => ({ render: () => ['native result'], invalidate() {} }) };
  const foreign = h.resolver('some_mcp_tool', () => native);
  assert.equal(foreign.renderShell, 'self');
  const foreignCtx = ctxFor();
  const panel = foreign.renderCall({ q: 1 }, theme, foreignCtx);
  foreign.renderResult({ content: [] }, { expanded: false }, theme, foreignCtx);
  const rows = text(panel, 40).map((l) => l.trim()).filter(Boolean);
  assert.deepEqual(rows, ['native call', 'native result']);
  assert.ok(widths(panel.render(40)).every((w) => w === 40));

  const own = { renderShell: 'self', renderCall: () => 'own' };
  assert.equal(h.resolver('custom', () => own), own, 'tools that draw their own shell keep their renderers');
  assert.equal(h.resolver('no_renderers').renderShell, 'self', 'tools without renderers still get a labelled panel');
  h.stop();
});

test('a tool renderer that throws never breaks the transcript', () => {
  const h = harness(); h.start();
  const throwing = { renderCall: () => { throw new Error('boom'); }, renderResult: () => { throw new Error('boom'); } };
  const foreign = h.resolver('flaky', () => throwing);
  const ctx = { state: {}, cwd: '/proj', isPartial: false, isError: false, expanded: false };
  const panel = foreign.renderCall({ target: 'x' }, theme, ctx);
  foreign.renderResult({ content: [{ type: 'text', text: 'out' }] }, { expanded: false }, theme, ctx);
  const rows = panel.render(40).map((line) => line.replace(/\x1b\[[0-9;]*m/g, '').trim()).filter(Boolean);
  assert.ok(rows[0].startsWith('flaky') && rows[0].includes('target=x'), 'falls back to the tool name and arguments');
  h.stop();
});
