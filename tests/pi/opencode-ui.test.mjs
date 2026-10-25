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
  const messages = [];
  const pi = { on: (name, handler) => handlers.set(name, handler), registerToolRenderer: (fn) => { resolver = fn; } };
  const ctx = { mode, cwd: '/proj', sessionManager: { getEntries: () => [], getEntryCount: () => 0, getSessionId: () => 's' }, getContextUsage: () => undefined, ui: { theme, setEditorComponent: (f) => calls.push(['editor', f]), setFooter: (f) => calls.push(['footer', f]), setHeader: (f) => calls.push(['header', f]), setWorkingMessage: (message) => messages.push(message) } };
  install(pi);
  return { handlers, ctx, calls, messages, resolver: (name, next = () => undefined) => resolver(name, next), start: () => handlers.get('session_start')({}, ctx), stop: () => handlers.get('session_shutdown')({}, ctx) };
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

// --- syntax-highlighted diffs, turn summary, live activity, footer statuses ----------------------------------

const tag = (text) => `«${text}»`;

test('highlightDiffRows colours each side as its own listing and starts a new one after a gap', () => {
  const rows = core.parseDiff([' 1 /* start', '-2 old line', '+2 new line', ' 3 end */', '  ...', ' 9 tail'].join('\n'));
  const seen = [];
  const colored = core.highlightDiffRows(rows, (code) => { seen.push(code); return code.split('\n').map(tag); });
  assert.deepEqual(seen, ['/* start\nold line\nend */', '/* start\nnew line\nend */', 'tail', 'tail'], 'old side, then new side, and each side again after the gap');
  assert.deepEqual(colored, [tag('/* start'), tag('old line'), tag('new line'), tag('end */'), undefined, tag('tail')]);
  const ragged = core.parseDiff([' 1 a', '-2 b', '+2 c'].join('\n'));
  assert.deepEqual(core.highlightDiffRows(ragged, () => ['one line only']), [undefined, undefined, undefined], 'a highlighter that changes the line count is ignored');
  assert.deepEqual(core.highlightDiffRows([], () => []), []);
  assert.equal(core.highlightDiffRows(core.parseDiff(' 1 a\t-b'), (code) => [code.replace('\t', '<tab>')])[0].includes('<tab>'), false, 'tabs are expanded before highlighting');
});

test('diffBlock draws the highlighter output and falls back to plain text per row', () => {
  const rows = core.parseDiff([' 1 keep', '-2 gone', '+2 here'].join('\n'));
  const style = { fg: (_token, text) => text, bgs: { ctx: BG, add: BG, del: BG }, code: () => [tag('keep'), undefined, tag('here')] };
  const block = core.diffBlock(rows, 40, style, 18).map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
  assert.ok(block[1].includes(tag('keep')) && block[3].includes(tag('here')));
  assert.ok(block[2].includes('gone') && !block[2].includes('«'), 'a row the highlighter skipped keeps the plain colour');
  assert.ok(widths(core.diffBlock(rows, 40, style, 18)).every((w) => w === 40));
});

const assistant = (timestamp, content, stopReason = 'stop') => ({ type: 'message', message: { role: 'assistant', timestamp, stopReason, content } });
const call = (id, name, args) => ({ type: 'toolCall', id, name, arguments: args });
const result = (toolCallId, toolName, details, isError = false) => ({ type: 'message', message: { role: 'toolResult', toolCallId, toolName, details, isError, content: [] } });

test('turnChanges totals the edit and write tools between one final answer and the next', () => {
  const entries = [
    { type: 'message', message: { role: 'user', timestamp: 1, content: 'go' } },
    assistant(2, [call('a', 'edit', { path: 'src/a.ts' }), call('b', 'write', { path: 'src/b.ts', content: 'x\ny\nz\n' })], 'toolUse'),
    result('a', 'edit', { diff: ' 1 keep\n-2 old\n+2 new\n+3 more' }),
    result('b', 'write', {}),
    assistant(3, [call('c', 'edit', { path: 'src/a.ts' }), call('d', 'edit', { path: 'src/c.ts' })], 'toolUse'),
    result('c', 'edit', { diff: '-1 x\n+1 y' }),
    result('d', 'edit', { diff: '+1 z' }, true),
    assistant(4, [{ type: 'text', text: 'done' }]),
    assistant(5, [{ type: 'text', text: 'nothing changed' }]),
  ];
  const changes = core.turnChanges(entries);
  assert.deepEqual(changes.get(4), { files: 2, added: 6, removed: 2 }, 'a file edited twice counts once; a failed edit counts for nothing');
  assert.equal(changes.has(5), false, 'an answer that changed nothing has no summary');
  assert.equal(changes.has(3), false, 'only a final answer carries a summary');
  const style = { fg: (_token, text) => text };
  assert.equal(core.formatChanges({ files: 1, added: 5, removed: 0 }, style), '✎ 1 file +5');
  assert.equal(core.formatChanges({ files: 3, added: 0, removed: 2 }, style), '✎ 3 files −2');
});

test('describeActivity and workingMessage say what is running and, once it matters, for how long', () => {
  assert.equal(core.describeActivity('read', { path: '/proj/src/a.ts' }, '/proj'), 'Reading src/a.ts');
  assert.equal(core.describeActivity('edit', { file_path: '/proj/b.ts' }, '/proj'), 'Editing b.ts');
  assert.equal(core.describeActivity('grep', { pattern: 'isExpired' }), 'Searching isExpired');
  assert.equal(core.describeActivity('bash', { command: 'nix build .#checks\nsecond line' }), 'Running nix build .#checks');
  assert.ok(core.describeActivity('bash', { command: 'x'.repeat(100) }).length <= 'Running '.length + 48);
  assert.equal(core.describeActivity('mcp__github__search_code', {}), 'github search code');
  assert.equal(core.describeActivity('read', {}), 'Reading');
  assert.equal(core.workingMessage('Running ls', 1200), 'Running ls');
  assert.equal(core.workingMessage('Running ls', 72000), 'Running ls · 1m 12s');
});

test('footerStatuses shows a non-default role as a badge, drops constants and keeps the rest', () => {
  const statuses = (entries) => new Map(Object.entries(entries));
  assert.deepEqual(core.footerStatuses(statuses({ 'model-roles': 'role: default', lsp: 'LSP gopls ●' })), { rest: ['LSP gopls ●'] });
  assert.deepEqual(core.footerStatuses(statuses({ 'model-roles': 'role: plan' })), { role: 'plan', rest: [] });
  assert.deepEqual(core.footerStatuses(statuses({ 'model-roles': 'slow → llm-platform/claude • high', 'ast-grep': 'ast-grep RW', todo: 'todo 1/3' })), { role: 'slow', rest: ['todo 1/3'] });
  assert.deepEqual(core.footerStatuses(statuses({ 'model-roles': 'default → p/m • medium' })), { rest: [] });
  assert.deepEqual(core.footerStatuses(statuses({ blank: '  \n ' })), { rest: [] });
});

test('the working row follows the tool that runs, ignores nested calls and is restored when the run ends', () => {
  const h = harness(); h.start();
  h.handlers.get('agent_start')({}, h.ctx);
  assert.equal(h.messages.at(-1), 'Working');
  h.handlers.get('tool_execution_start')({ toolName: 'read', args: { path: '/proj/a.ts' } }, h.ctx);
  assert.equal(h.messages.at(-1), 'Reading a.ts');
  h.handlers.get('tool_execution_start')({ toolName: 'bash', args: { command: 'ls' }, parentToolCallId: 'x' }, h.ctx);
  assert.equal(h.messages.at(-1), 'Reading a.ts', 'a call made by another tool does not take over the row');
  h.handlers.get('tool_execution_end')({ toolName: 'read' }, h.ctx);
  assert.equal(h.messages.at(-1), 'Working');
  h.handlers.get('agent_end')({}, h.ctx);
  assert.equal(h.messages.at(-1), undefined, 'the default working message returns');
  h.stop();
});

test('the footer shows the role badge, the context and the remaining statuses, and keeps a narrow row legible', () => {
  const h = harness();
  h.ctx.getContextUsage = () => ({ tokens: 54000, percent: 21 });
  h.start();
  const factory = h.calls.find(([kind]) => kind === 'footer')[1];
  const data = (statuses) => ({ getGitBranch: () => 'feat/x', getExtensionStatuses: () => new Map(Object.entries(statuses)), onBranchChange: () => () => {} });
  const plain = (lines) => lines.map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
  const render = (statuses, width) => {
    const component = factory({ requestRender() {} }, theme, data(statuses));
    const lines = component.render(width);
    component.dispose();
    return plain(lines)[0];
  };
  const wide = render({ 'model-roles': 'role: plan', lsp: 'LSP gopls ●', 'ast-grep': 'ast-grep RW' }, 100);
  assert.ok(wide.startsWith(' ~') || wide.includes('feat/x'), wide);
  assert.ok(wide.includes('plan') && wide.includes('54K (21%)') && wide.includes('LSP gopls ●') && !wide.includes('ast-grep'), wide);
  assert.ok(!render({ 'model-roles': 'role: default' }, 100).includes('role'), 'the default role is not a badge');
  assert.ok(visibleWidth(render({ lsp: 'LSP gopls ●' }, 30)) <= 30, 'a narrow row is cut, never wrapped');
  h.stop();
});

test('the todo tool is one inline line, because the checklist above the prompt shows the list', () => {
  const h = harness(); h.start();
  const todo = h.resolver('todo');
  assert.equal(todo.renderShell, 'self');
  const ctx = { state: {}, cwd: '/proj', isPartial: false, isError: false, expanded: false };
  const rows = (component) => component.render(60).map((line) => line.replace(/\x1b\[[0-9;]*m/g, '').trim());
  assert.deepEqual(rows(todo.renderCall({ op: 'init', items: ['a', 'b', 'c'] }, theme, ctx)), ['◈ Todo init 3 tasks']);
  assert.deepEqual(rows(todo.renderCall({ op: 'done', id: 2 }, theme, ctx)), ['◈ Todo done #2']);
  assert.deepEqual(rows(todo.renderResult({ content: [{ type: 'text', text: 'Todos: 1/3 done' }] }, { expanded: false }, theme, ctx)), [], 'the result text is not repeated');
  h.stop();
});

test('keepForeground reopens the text colour after every reset and leaves explicit colours alone', () => {
  const FG = '\x1b[38;2;9;9;9m';
  assert.equal(core.keepForeground('a\x1b[38;2;1;2;3mb\x1b[39mc\x1b[0md', FG), FG + 'a\x1b[38;2;1;2;3mb\x1b[39m' + FG + 'c\x1b[0m' + FG + 'd');
  assert.equal(core.keepForeground('\x1b[0;31mx', FG), FG + '\x1b[0;31mx', 'a reset that also sets a colour needs no reopening');
  assert.equal(core.keepForeground('\x1b[48;2;1;2;3mx', FG), FG + '\x1b[48;2;1;2;3mx', 'a background is not a foreground reset');
});

test('the activity timer stops with the session and a retired context is never touched; a headless instance leaves the row alone', async () => {
  const h = harness(); h.start();
  h.handlers.get('agent_start')({}, h.ctx);
  h.handlers.get('tool_execution_start')({ toolName: 'bash', args: { command: 'sleep 9' } }, h.ctx);
  await new Promise((resolve) => setTimeout(resolve, 1200));
  assert.ok(h.messages.filter((m) => m === 'Running sleep 9').length >= 2, 'the ticker refreshed the row');
  h.stop();
  const settled = h.messages.length;
  await new Promise((resolve) => setTimeout(resolve, 1200));
  assert.equal(h.messages.length, settled, 'no refresh after the session ended');

  // A context that throws once the session is retired must not crash an event that still arrives.
  const retired = harness(); retired.start();
  Object.defineProperty(retired.ctx.ui, 'setWorkingMessage', { value() { throw new Error('This extension ctx is stale'); } });
  retired.handlers.get('agent_start')({}, retired.ctx);
  retired.handlers.get('agent_end')({}, retired.ctx);
  retired.stop();

  // An instance that never started a TUI session ignores run events.
  const headless = harness('json'); headless.start();
  headless.handlers.get('agent_start')({}, headless.ctx);
  headless.handlers.get('tool_execution_start')({ toolName: 'read', args: { path: 'x' } }, headless.ctx);
  assert.deepEqual(headless.messages, [], 'a headless session does not drive a working row');
  headless.stop();
});

test('the answer footer is cut to the width, and the change summaries follow the branch', () => {
  const proto = host.AssistantMessageComponent.prototype, original = proto.render;
  proto.render = () => ['reply'];
  try {
    const h = harness();
    let leaf = 'a';
    const branches = {
      a: [assistant(9, [call('c1', 'edit', { path: 'x.ts' })], 'toolUse'), result('c1', 'edit', { diff: '+1 new' }), assistant(10, [{ type: 'text', text: 'done' }])],
      b: [assistant(10, [{ type: 'text', text: 'done' }])],
    };
    h.ctx.sessionManager = { getEntries: () => [], getEntryCount: () => 5, getSessionId: () => 's', getLeafId: () => leaf, getBranch: () => branches[leaf] };
    h.ctx.model = { id: 'm' };
    h.start();
    const finished = (width) => proto.render.call({ lastMessage: { stopReason: 'stop', provider: 'p', model: 'a-very-long-model-name-for-a-narrow-terminal', timestamp: 10 }, isStreaming: false, hasToolCalls: false }, width);
    const plain = (lines) => lines.map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
    assert.ok(plain(finished(80)).at(-1).includes('\u270e 1 file +1'), 'branch a changed a file');
    leaf = 'b';
    assert.ok(!plain(finished(80)).at(-1).includes('\u270e'), 'branch b did not, though the entry count is the same');
    for (const width of [12, 20, 30, 80]) assert.ok(widths(finished(width)).every((w) => w <= width), `every line fits ${width} columns`);
    h.stop();
  } finally { proto.render = original; }
});

// --- shell commands that write files: heredoc bodies, command colours, the executed command ------------------

test('findHeredocs reads the target, the interpreter and the body of every heredoc', () => {
  const doc = (command) => core.findHeredocs(command);
  assert.deepEqual(doc("cat > main.go <<'E'\npackage main\n\nfunc main() {}\nE\ngofmt -l main.go"), [{ target: 'main.go', append: false, interpreter: undefined, start: 1, end: 4 }]);
  assert.equal(doc("cat <<'EOF' > out.txt\nhello\nEOF")[0].target, 'out.txt', 'a redirect after the introducer counts');
  assert.deepEqual(doc("tee -a log.txt <<EOF\nline\nEOF").map((d) => [d.target, d.append]), [['log.txt', true]]);
  assert.deepEqual(doc("cat >> notes.md <<'X'\nmore\nX").map((d) => [d.target, d.append]), [['notes.md', true]]);
  assert.equal(doc("python3 - <<'PY'\nprint(1)\nPY")[0].interpreter, 'python3');
  assert.equal(doc("cat > a.sh <<-EOF\n\tbody\n\tEOF\nrm a.sh")[0].end, 2, 'with <<- the terminator may be tab-indented');
  assert.deepEqual(doc("grep x <<< 'a b'\nls"), [], 'a here-string is not a heredoc');
  assert.equal(doc("cat > f <<E\nno terminator\nat all")[0].end, 3, 'an unterminated body runs to the end');
  const two = doc("cat <<A > a.txt; cat <<B > b.txt\none\nA\ntwo\nB");
  assert.deepEqual(two.map((d) => [d.target, d.start, d.end]), [['a.txt', 1, 2], ['b.txt', 3, 4]]);
  assert.deepEqual(core.heredocWrites("cat > main.go <<'E'\na\nb\nE\ncat > /dev/null <<E\nx\nE\ncat > \"$HOME/x\" <<E\ny\nE"), [{ path: 'main.go', lines: 2 }]);
});

test('highlightCommand colours a heredoc body as the language of its file and the rest as shell', () => {
  const tag = (code, language) => code.split('\n').map((line) => `[${language}]${line}`);
  const languageOf = (path) => ({ 'main.go': 'go', 'a.nix': 'nix' })[path];
  const lines = core.highlightCommand("cat > main.go <<'E'\npackage main\nfunc f() {}\nE\ngofmt -l main.go", tag, languageOf);
  assert.deepEqual(lines, ["[bash]cat > main.go <<'E'", '[go]package main', '[go]func f() {}', '[bash]E', '[bash]gofmt -l main.go']);
  // Shell lines on both sides of a body are separate listings; a body in an unknown language stays plain.
  const unknown = core.highlightCommand("cat > data.xyz <<E\nraw\nE", tag, languageOf);
  assert.deepEqual(unknown, ['[bash]cat > data.xyz <<E', undefined, '[bash]E']);
  assert.deepEqual(core.highlightCommand("python3 - <<'PY'\nprint(1)\nPY", tag, languageOf)[1], '[python]print(1)');
  assert.deepEqual(core.highlightCommand('ls -la', tag, languageOf), ['[bash]ls -la']);
  // A highlighter that throws or changes the line count leaves the lines plain instead of breaking the panel.
  assert.deepEqual(core.highlightCommand('a\nb', () => { throw new Error('boom'); }, languageOf), [undefined, undefined]);
  assert.deepEqual(core.highlightCommand('a\nb', () => ['one line'], languageOf), [undefined, undefined]);
});

test('shellBlock draws the coloured command and, when a hook rewrote it, what actually ran', () => {
  const style = { bg: BG, fg: (_token, text) => text, command: (command) => command.split('\n').map((line) => `<<${line}>>`) };
  const base = { command: 'ls -la', output: 'a.txt', maxLines: 5, pending: false, expanded: false, hint: 'ctrl+o to expand' };
  const text = (lines) => lines.map((line) => line.replace(/\x1b\[[0-9;]*m/g, '').trimEnd());
  const plain = text(core.shellBlock(base, 60, style));
  assert.ok(plain.some((line) => line.includes('$ <<ls -la>>')), 'the first line carries the prompt and the colours');
  assert.ok(!plain.some((line) => line.includes('\u21b3')), 'an untouched command shows no second line');
  const rewritten = text(core.shellBlock({ ...base, ran: 'rtk ls -la' }, 60, style));
  assert.ok(rewritten.some((line) => line.includes('\u21b3 rtk ls -la')), rewritten.join('\n'));
  assert.ok(!text(core.shellBlock({ ...base, ran: 'ls -la' }, 60, style)).some((line) => line.includes('\u21b3')), 'a command that ran as written shows nothing');
  const multi = text(core.shellBlock({ ...base, command: 'cat > f <<E\nbody\nE' }, 60, style));
  assert.deepEqual(multi.filter((line) => line.includes('<<')).map((line) => line.trim()), ['$ <<cat > f <<E>>', '<<body>>', '<<E>>'], 'continuation lines keep their own colours');
  assert.ok(widths(core.shellBlock({ ...base, command: 'x'.repeat(200), ran: 'y'.repeat(200) }, 40, style)).every((w) => w === 40), 'long commands wrap inside the panel');
});

test('turnChanges counts a file written through a heredoc like a write', () => {
  const entries = [
    assistant(2, [call('b1', 'bash', { command: "cat > foobar.go <<'E'\npackage main\n\nfunc foobar() {}\nE\ngofmt -l foobar.go" })], 'toolUse'),
    result('b1', 'bash', undefined),
    assistant(3, [call('b2', 'bash', { command: 'ls -la' })], 'toolUse'),
    result('b2', 'bash', undefined),
    assistant(4, [call('b3', 'bash', { command: 'cat > broken.go <<E\nx\nE' })], 'toolUse'),
    result('b3', 'bash', undefined, true),
    assistant(5, [{ type: 'text', text: 'done' }]),
  ];
  assert.deepEqual(core.turnChanges(entries).get(5), { files: 1, added: 3, removed: 0 }, 'one file, three lines; a failed command and a read-only one count for nothing');
});

test('the bash panel says what actually ran when a hook rewrote the command, and only then', () => {
  const h = harness(); h.start();
  const ctxFor = (extra = {}) => ({ state: {}, cwd: '/proj', isPartial: false, isError: false, expanded: false, ...extra });
  const text = (component, width = 70) => component.render(width).map((line) => line.replace(/\x1b\[[0-9;]*m/g, '').trimEnd());
  const bash = h.resolver('bash');
  // rtk rewrote this one: the transcript still carries the model's command, tool_result carries the executed input.
  h.handlers.get('tool_result')({ toolName: 'bash', toolCallId: 't1', input: { command: 'rtk ls -la' } }, h.ctx);
  const rewrittenCtx = ctxFor({ toolCallId: 't1' });
  const rewritten = bash.renderCall({ command: 'ls -la' }, theme, rewrittenCtx);
  bash.renderResult({ content: [{ type: 'text', text: '644 a.txt 3B' }] }, { expanded: false }, theme, rewrittenCtx);
  const rows = text(rewritten);
  assert.ok(rows.some((line) => line.includes('$ ls -la')), 'the model\'s command stays as the first line');
  assert.ok(rows.some((line) => line.trim() === '\u21b3 rtk ls -la'), rows.join('\n'));
  // Left alone: executed equals asked, or no tool_result was seen.
  h.handlers.get('tool_result')({ toolName: 'bash', toolCallId: 't2', input: { command: 'echo hi' } }, h.ctx);
  const same = ctxFor({ toolCallId: 't2' });
  assert.ok(!text(bash.renderCall({ command: 'echo hi' }, theme, same)).some((line) => line.includes('\u21b3')));
  assert.ok(!text(bash.renderCall({ command: 'echo hi' }, theme, ctxFor({ toolCallId: 'unseen' }))).some((line) => line.includes('\u21b3')));
  // Other tools never record anything.
  h.handlers.get('tool_result')({ toolName: 'read', toolCallId: 't3', input: { path: 'x' } }, h.ctx);
  h.handlers.get('tool_result')({ toolName: 'bash', toolCallId: 't4' }, h.ctx);
  h.stop();
});
