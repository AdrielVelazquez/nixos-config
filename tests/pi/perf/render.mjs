// Render cost of the opencode skin: CPU milliseconds per call for the panels a long transcript redraws on every frame.
// Pi repaints the whole transcript, so what matters is the warm cost (nothing changed since the last frame) times the
// number of panels; the cold cost is paid once per panel. CPU time, not wall time, so a busy machine does not skew it.
// Usage: PI_TEST_PACKAGE_DIR=<pi package dir> node tests/pi/perf/render.mjs [--panels N] [--budget-ms MS]
import { createRequire } from 'node:module';
import { resolve } from 'node:path';

const sdk = process.env.PI_TEST_PACKAGE_DIR;
if (!sdk) throw new Error('set PI_TEST_PACKAGE_DIR to the Pi package directory');
const arg = (name, fallback) => { const i = process.argv.indexOf(name); return i > 0 ? Number(process.argv[i + 1]) : fallback; };
const panels = arg('--panels', 200);
const budget = arg('--budget-ms', 0);

const { createJiti } = createRequire(`${sdk}/package.json`)('jiti');
const jiti = createJiti(import.meta.url, { alias: {
  '@earendil-works/pi-coding-agent': `${sdk}/dist/index.js`,
  '@earendil-works/pi-tui': `${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`,
} });
const host = await jiti.import(`${sdk}/dist/index.js`);
const { rgbColor } = await jiti.import(`${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`);
const { default: install } = await jiti.import(resolve('dotfiles/pi/extensions/opencode-ui.ts'));
host.initTheme('dark');

const BG = '\x1b[48;2;20;20;20m';
const theme = {
  getColorMode: () => 'truecolor', getBgAnsi: () => BG, getFgAnsi: () => '\x1b[38;2;238;238;238m',
  fg: (_token, text) => `\x1b[38;2;1;2;3m${text}\x1b[39m`, bold: (text) => text,
  colors: { userMessageBg: rgbColor(20, 20, 20), toolSuccessBg: rgbColor(20, 20, 20), toolDiffAdded: rgbColor(0, 255, 0), toolDiffRemoved: rgbColor(255, 0, 0) },
};
const handlers = new Map();
let resolver;
install({ on: (name, handler) => handlers.set(name, handler), registerToolRenderer: (fn) => { resolver = fn; } });
const ctx = { mode: 'tui', cwd: '/proj', sessionManager: { getEntries: () => [], getEntryCount: () => 0, getSessionId: () => 's' }, getContextUsage: () => undefined,
  ui: { theme, setEditorComponent() {}, setFooter() {}, setHeader() {}, setStatus() {}, setWidget() {}, setWorkingMessage() {}, setWorkingIndicator() {}, setTitle() {}, setToolsExpanded() {}, notify() {}, onTerminalInput: () => () => {} } };

const cpu = () => { const u = process.cpuUsage(); return (u.user + u.system) / 1000; };
const time = (fn) => { const t = cpu(); fn(); return cpu() - t; };
const goFile = (n) => Array.from({ length: 24 }, (_, i) => i === 0 ? 'package main' : i === 2 ? `func f${n}(a, b int) int {` : `\tx${i} := a + b * ${i} // step ${i}`).join('\n');
const heredoc = (n) => `cat > f${n}.go <<'E'\n${goFile(n)}\nE\ngofmt -l f${n}.go`;
const diff = (n) => Array.from({ length: 120 }, (_, i) => (i % 9 === 4 ? `-${i + 1} \treturn old${n}(${i})` : i % 9 === 5 ? `+${i + 1} \treturn updated${n}(${i}, ctx)` : ` ${i + 1} \tvalue${i} := compute(${i}) // ${n}`)).join('\n');
const output = Array.from({ length: 60 }, (_, i) => `  running case ${i} ... ok`).join('\n');

const rows = [];
const scenario = (name, build) => {
  const components = Array.from({ length: panels }, (_, n) => build(n));
  const cold = time(() => components.forEach((c) => c.render(110)));
  const warm = [];
  for (let frame = 0; frame < 5; frame++) warm.push(time(() => components.forEach((c) => c.render(110))));
  warm.sort((a, b) => a - b);
  rows.push({ name, cold: cold / panels, warm: warm[2] / panels, frame: warm[2] });
};

// Pi's own assistant message, drawn first as Pi does and then through the skin's wrapper around it.
const answer = (n) => ({ role: 'assistant', content: [{ type: 'text', text: [`Answer ${n}: the change is small.`, '', '```go', ...goFile(n).split('\n'), '```', '', ...Array.from({ length: 12 }, (_, i) => `- point ${i} about \`value${i}\` and **why** it matters`)].join('\n') }], stopReason: 'stop', provider: 'p', model: 'm', timestamp: 1000 + n, usage: {} });
const assistant = (n) => new host.AssistantMessageComponent(answer(n));
scenario('assistant: markdown answer, skin off', assistant);
handlers.get('session_start')?.({}, ctx);
scenario('assistant: markdown answer, skin on', assistant);

const bash = resolver('bash', () => undefined);
const edit = resolver('edit', () => undefined);
let id = 0;
const callCtx = (extra = {}) => ({ state: {}, cwd: '/proj', isPartial: false, isError: false, expanded: false, toolCallId: `t${id++}`, ...extra });
const withResult = (renderer, args, result, extra) => {
  const c = callCtx(extra);
  const call = renderer.renderCall(args, theme, c);
  renderer.renderResult(result, { expanded: false }, theme, c);
  return call;
};

scenario('bash: heredoc write, 24-line body', (n) => withResult(bash, { command: heredoc(n) }, { content: [{ type: 'text', text: '(no output)' }] }));
scenario('bash: plain command, 60 output lines', (n) => withResult(bash, { command: `go test ./pkg${n}/... -run Test${n} -count=1` }, { content: [{ type: 'text', text: output }] }));
scenario('edit: 120-row diff', (n) => {
  const c = callCtx();
  const call = edit.renderCall({ path: `src/file${n}.go` }, theme, c);
  const result = edit.renderResult({ content: [], details: { diff: diff(n) } }, { expanded: false }, theme, c);
  return { render: (w) => [...call.render(w), ...(result?.render(w) ?? [])] };
});

const pad = (s, n) => String(s).padEnd(n);
console.log(`${pad('scenario', 40)} ${pad('cold ms', 9)} ${pad('warm ms', 9)} warm ms for ${panels} panels (one frame)`);
for (const r of rows) console.log(`${pad(r.name, 40)} ${pad(r.cold.toFixed(3), 9)} ${pad(r.warm.toFixed(3), 9)} ${r.frame.toFixed(1)}`);
const worst = Math.max(...rows.map((r) => r.frame));
if (budget && worst > budget) { console.error(`FAIL: a warm frame of ${panels} panels costs ${worst.toFixed(1)} ms of CPU, budget ${budget} ms`); process.exit(1); }
handlers.get('session_shutdown')?.({}, ctx);
