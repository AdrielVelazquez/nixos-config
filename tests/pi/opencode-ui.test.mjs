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
  const notes = [];
  const tools = [];
  const pi = { on: (name, handler) => handlers.set(name, handler), registerToolRenderer: (fn) => { resolver = fn; }, getAllTools: () => tools };
  const visibility = [];
  const ctx = { mode, cwd: '/proj', sessionManager: { getEntries: () => [], getEntryCount: () => 0, getSessionId: () => 's' }, getContextUsage: () => undefined, ui: { theme, setEditorComponent: (f) => calls.push(['editor', f]), setFooter: (f) => calls.push(['footer', f]), setHeader: (f) => calls.push(['header', f]), setWorkingMessage: (message) => messages.push(message), setWorkingVisible: (visible) => visibility.push(visible), notify: (message, type) => notes.push([message, type]) } };
  install(pi);
  return { handlers, ctx, calls, messages, notes, tools, visibility, resolver: (name, next = () => undefined) => resolver(name, next), start: () => handlers.get('session_start')({}, ctx), stop: () => handlers.get('session_shutdown')({}, ctx) };
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

test('live activity replaces the path in the footer, keeps total elapsed time, and returns to the path when idle', () => {
  const h = harness();
  const originalNow = Date.now;
  let clock = 100000;
  Date.now = () => clock;
  h.start();
  const component = h.calls.find(([kind]) => kind === 'footer')[1]({ requestRender() {} }, theme, { getGitBranch: () => 'feat/x', getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} });
  const line = (width = 140) => core.stripAnsi(component.render(width)[0]);
  try {
    assert.deepEqual(h.visibility, [false], 'the native working row is hidden');
    assert.ok(line().includes('/proj') && line().includes('feat/x'));
    h.handlers.get('agent_start')({}, h.ctx);
    const first = line();
    assert.ok(first.includes('Working') && !first.includes('/proj'), first);
    clock += 160;
    assert.notEqual(line().trim().slice(0, 4), first.trim().slice(0, 4), 'the activity animation advances');
    clock = 112000;
    h.handlers.get('tool_execution_start')({ toolName: 'read', args: { path: '/proj/a.ts' } }, h.ctx);
    assert.ok(line().includes('Reading a.ts') && line().includes('12s'), line());
    h.handlers.get('tool_execution_start')({ toolName: 'bash', args: { command: 'ls' }, parentToolCallId: 'x' }, h.ctx);
    assert.ok(line().includes('Reading a.ts'), 'nested tools do not take over the footer');
    h.ctx.ui.notify('MCP servers need attention:\n  reddit-tools: needs sign-in\nRun /mcp to fix.', 'warning');
    h.handlers.get('tool_execution_start')({ toolName: 'read', args: { path: '/proj/' + 'long/'.repeat(30) } }, h.ctx);
    assert.ok(line(80).includes('1 sign in'), 'attention survives a verbose activity');
    for (const width of [1, 8, 20, 40, 80]) assert.ok(visibleWidth(line(width)) <= width, `footer fits ${width} columns`);
    h.handlers.get('tool_execution_end')({ toolName: 'read' }, h.ctx);
    assert.ok(line().includes('Working') && line().includes('12s'), 'tool changes do not reset total run time');
    assert.deepEqual(h.messages, [], 'there is no second working message above the editor');
    h.handlers.get('agent_end')({}, h.ctx);
    assert.ok(line().includes('/proj') && !line().includes('Working'), 'the path returns at the end');
  } finally {
    component.dispose();
    h.stop();
    Date.now = originalNow;
  }
  assert.deepEqual(h.visibility, [false, true], 'the native row is restored when the skin shuts down');
});

test('the footer shows the context, MCP health and the remaining statuses in grey, and keeps a narrow row legible', () => {
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
  const wide = render({ 'model-roles': 'role: plan', lsp: 'LSP gopls ●', 'ast-grep': 'ast-grep RW' }, 140);
  assert.ok(wide.startsWith(' ~') || wide.includes('feat/x'), wide);
  assert.ok(wide.includes('54K (21%)') && wide.includes('LSP gopls ●') && !wide.includes('ast-grep') && !wide.includes('plan'), wide);
  assert.ok(wide.includes('shift+tab agents') && wide.includes('/ commands'), wide);
  assert.ok(!wide.includes('MCP') && !wide.includes('connected'), 'no servers, no MCP summary');
  assert.ok(visibleWidth(render({ lsp: 'LSP gopls ●' }, 30)) <= 30, 'a narrow row is cut, never wrapped');
  const coloured = factory({ requestRender() {} }, theme, data({ lsp: '\x1b[31mLSP down\x1b[39m' })).render(140)[0];
  assert.ok(!coloured.includes('\x1b[31m'), 'statuses are repainted in the footer grey');
  h.stop();
});

test('the footer counts connected servers and shows errors and sign-ins only when there are some', () => {
  const h = harness();
  h.tools.push({ name: 'mcp__a__t', namespace: { name: 'mcp__a', aliases: ['a'] } }, { name: 'mcp__b__t', namespace: { name: 'mcp__b', aliases: ['b'] } }, { name: 'read' });
  h.start();
  const factory = h.calls.find(([kind]) => kind === 'footer')[1];
  const render = () => {
    const component = factory({ requestRender() {} }, theme, { getGitBranch: () => null, getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} });
    const line = component.render(140)[0].replace(/\x1b\[[0-9;]*m/g, '');
    component.dispose();
    return line;
  };
  assert.ok(render().includes('2 connected') && !render().includes('sign in') && !render().includes('error'));
  h.ctx.ui.notify('MCP servers need attention:\n  reddit-tools: needs sign-in\n  broken: failed: boom\nRun /mcp to fix.', 'warning');
  const line = render();
  assert.ok(line.includes('2 connected') && line.includes('1 sign in') && line.includes('1 error'), line);
  assert.deepEqual(h.notes, [], 'a splash warning is shown only in the notification box');
  h.handlers.get('input')({ text: 'hi' }, h.ctx);
  h.ctx.ui.notify('Later warning', 'warning');
  assert.deepEqual(h.notes.at(-1), ['Later warning', 'warning'], 'normal notifications return after the splash');
  h.stop();
});

test('hidden MCP tools do not count as connected or hide a reported failure', () => {
  const h = harness();
  h.tools.push({ name: 'mcp__a__t', exposure: 'codemode', namespace: { name: 'mcp__a', aliases: ['a'] } }, { name: 'mcp__b__t', exposure: 'hidden', namespace: { name: 'mcp__b', aliases: ['b'] } });
  h.start();
  const component = h.calls.find(([kind]) => kind === 'footer')[1]({ requestRender() {} }, theme, { getGitBranch: () => null, getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} });
  try {
    h.ctx.ui.notify('MCP servers need attention:\n  b: failed: gone\nRun /mcp to fix.', 'warning');
    const failed = core.stripAnsi(component.render(140)[0]);
    assert.ok(failed.includes('1 connected') && failed.includes('1 error'), failed);
    h.tools[1].exposure = 'codemode';
    h.ctx.ui.notify('b reconnected', 'info');
    const recovered = core.stripAnsi(component.render(140)[0]);
    assert.ok(recovered.includes('2 connected') && !recovered.includes('error'), recovered);
  } finally { component.dispose(); h.stop(); }
});

test('a new session opens on the splash with its notification, and the first input replaces it with the compact header', () => {
  const h = harness();
  h.start();
  const factory = h.calls.find(([kind]) => kind === 'header')[1];
  const tui = { terminal: { rows: 40 }, requestRender() {} };
  const component = factory(tui, theme);
  const plain = (lines) => lines.map((line) => line.replace(/\x1b\[[0-9;]*m/g, ''));
  assert.ok(plain(component.render(100)).some((line) => line.includes('█')), 'the wordmark');
  h.ctx.ui.notify('MCP servers need attention:\n  reddit-tools: needs sign-in\nRun /mcp to fix.', 'warning');
  const withToast = plain(component.render(100));
  assert.ok(withToast.some((line) => line.includes('reddit-tools: needs sign-in') && line.includes('│')), 'the notification box');
  assert.ok(withToast.every((line) => visibleWidth(line) <= 100), 'every splash row fits');
  h.handlers.get('input')({ text: 'hi' }, h.ctx);
  const after = plain(component.render(100));
  assert.ok(!after.some((line) => line.includes('reddit-tools') || line.includes('█')) && after.some((line) => line.includes('commands')), 'compact header only');
  h.ctx.sessionManager.getEntries = () => [{ type: 'message' }];
  h.start();
  assert.ok(!plain(h.calls.filter(([kind]) => kind === 'header').at(-1)[1](tui, theme).render(100)).some((line) => line.includes('█')), 'a session with messages gets no splash');
  h.stop();
});

test('a headless child input does not dismiss the parent splash, and short terminals get a compact header', () => {
  const parent = harness(); parent.start();
  const child = harness('json'); child.start();
  const factory = parent.calls.find(([kind]) => kind === 'header')[1];
  try {
    child.handlers.get('input')({ text: 'delegated task' }, child.ctx);
    assert.ok(factory({ terminal: { rows: 40 }, requestRender() {} }, theme).render(100).some(line => line.includes('█')), 'the parent splash stays visible');
    assert.ok(factory({ terminal: { rows: 12 }, requestRender() {} }, theme).render(100).length <= 4, 'the header leaves room for the editor in a short terminal');
  } finally { child.stop(); parent.stop(); }
});

test('core: role labels, the startup report and MCP health', () => {
  assert.deepEqual([undefined, 'default', 'plan', 'slow'].map(core.roleLabel), ['Build', 'Build', 'Plan', 'Slow']);
  assert.deepEqual([...core.parseMcpAttention('MCP servers need attention:\n  a: needs sign-in\n  b: failed: no route\n  config: bad json\nRun /mcp to fix.')], [['a', 'signin'], ['b', 'error'], ['config: bad json', 'error']]);
  assert.equal(core.parseMcpAttention('something else').size, 0);
  assert.deepEqual(core.mcpHealth(new Set(['a', 'c']), new Map([['a', 'signin'], ['b', 'error']])), { connected: 2, errors: 1, signin: 0 });
  assert.deepEqual(core.footerStatuses(new Map([['model-roles', 'role: plan'], ['model-role-consumer', 'tiny → fixture/small • low']])), { role: 'plan', rest: [] });
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

test('the footer animation stops on reload and shutdown; headless sessions leave the loader alone', async () => {
  const h = harness(); h.start();
  let renders = 0;
  const component = h.calls.find(([kind]) => kind === 'footer')[1]({ requestRender() { renders++; } }, theme, { getGitBranch: () => null, getExtensionStatuses: () => new Map(), onBranchChange: () => () => {} });
  try {
    h.handlers.get('agent_start')({}, h.ctx);
    await new Promise((resolve) => setTimeout(resolve, 380));
    assert.ok(renders >= 2, 'the footer animation is repainted');
    h.start();
    const settled = renders;
    await new Promise((resolve) => setTimeout(resolve, 380));
    assert.equal(renders, settled, 'reload stops the old animation');
    h.handlers.get('agent_start')({}, h.ctx);
    h.stop();
    const stopped = renders;
    await new Promise((resolve) => setTimeout(resolve, 380));
    assert.equal(renders, stopped, 'shutdown stops the animation');
  } finally { component.dispose(); h.stop(); }
  const headless = harness('json'); headless.start();
  headless.handlers.get('agent_start')({}, headless.ctx);
  headless.handlers.get('tool_execution_start')({ toolName: 'read', args: { path: 'x' } }, headless.ctx);
  assert.deepEqual(headless.visibility, [], 'a headless session never hides the native loader');
  assert.deepEqual(headless.messages, []);
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

// --- frames: Pi repaints the whole transcript constantly, so an unchanged panel must not be laid out again ------

test('a bash panel is laid out again only when something it shows changed', () => {
  const h = harness(); h.start();
  const bash = h.resolver('bash');
  const ctx = { state: {}, cwd: '/proj', isPartial: true, isError: false, expanded: false, toolCallId: 'f1', durationMs: undefined };
  const panel = bash.renderCall({ command: "cat > a.go <<'E'\npackage a\nE" }, theme, ctx);
  const first = panel.render(80);
  assert.strictEqual(panel.render(80), first, 'nothing changed: the same lines come back');
  assert.notStrictEqual(panel.render(60), first, 'a new width is a new layout');
  assert.strictEqual(panel.render(60), panel.render(60));
  // The output arrives, the command finishes, ctrl+o expands, a hook's rewrite shows: each changes the panel.
  ctx.state.output = 'first line\nsecond line';
  assert.ok(panel.render(60).join('\n').includes('second line'), 'new output shows');
  ctx.isPartial = false;
  const settled = panel.render(60);
  assert.strictEqual(panel.render(60), settled);
  ctx.expanded = true;
  assert.notStrictEqual(panel.render(60), settled, 'expanding re-lays out');
  ctx.expanded = false;
  h.handlers.get('tool_result')({ toolName: 'bash', toolCallId: 'f1', input: { command: 'rtk x' } }, h.ctx);
  assert.ok(panel.render(60).join('\n').includes('\u21b3 rtk x'), 'a rewrite that is reported after the first frame still shows');
  ctx.isError = true;
  ctx.state.output = 'boom\n\nCommand exited with code 2';
  assert.ok(panel.render(60).join('\n').includes('exit 2'));
  const before = panel.render(60);
  panel.invalidate();
  assert.notStrictEqual(panel.render(60), before, 'invalidate drops the cached layout');
  assert.deepEqual(panel.render(60), before, 'and the new layout is the same one');
  h.stop();
});

test('the wrapper around Pi\'s answer component follows its content and reuses unchanged frames', () => {
  host.initTheme('dark');
  const message = (text, timestamp = 1) => ({ role: 'assistant', content: [{ type: 'text', text }], stopReason: 'stop', provider: 'p', model: 'm', timestamp, usage: {} });
  const plain = new host.AssistantMessageComponent(message('hello\n\n```go\nfunc f() {}\n```'));
  const h = harness(); h.start();
  try {
    const component = new host.AssistantMessageComponent(message('hello\n\n```go\nfunc f() {}\n```'));
    const first = component.render(80);
    assert.deepEqual(component.render(80), first, 'repeated frames are identical');
    assert.ok(first.join('\n').includes('func'), first.join('\n'));
    assert.ok(widths(first).every((w) => w <= 80));
    assert.notDeepEqual(component.render(50), first, 'a new width is laid out again');
    component.updateContent(message('changed text\n\n```go\nfunc g() {}\n```'));
    const changed = component.render(80).join('\n');
    assert.ok(changed.includes('changed text') && !changed.includes('hello'), 'new content shows on the next frame');
    assert.ok(plain.render(80).join('\n').length > 0, 'a component created before the skin keeps rendering');
  } finally { h.stop(); }
});
