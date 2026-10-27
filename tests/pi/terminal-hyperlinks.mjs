import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const [sdk, ...settingsFiles] = process.argv.slice(2);
process.env.TERM = 'xterm-256color';
process.env.TERM_PROGRAM = 'TUIOS';
for (const key of ['TMUX', 'KITTY_WINDOW_ID', 'GHOSTTY_RESOURCES_DIR', 'WEZTERM_PANE', 'ITERM_SESSION_ID',
  'WT_SESSION', 'WARP_SESSION_ID', 'WARP_TERMINAL_SESSION_UUID', 'TERMINAL_EMULATOR', 'PI_HYPERLINKS']) {
  delete process.env[key];
}

const { SettingsManager } = await import(`${sdk}/dist/core/settings-manager.js`);
const { Markdown, setCapabilityOverrides } = await import(`${sdk}/node_modules/@earendil-works/pi-tui/dist/index.js`);
const theme = new Proxy({}, { get: () => text => text });
const target = 'https://example.com/hyperlink-target';
const openLink = `\x1b]8;;${target}\x1b\\`;

for (const entry of settingsFiles) {
  const separator = entry.indexOf('=');
  const name = entry.slice(0, separator);
  const settings = JSON.parse(readFileSync(entry.slice(separator + 1), 'utf8'));
  setCapabilityOverrides(SettingsManager.inMemory(settings).getTerminalCapabilityOverrides());
  for (const [label, width] of [['main word', 80], ['wrapped label '.repeat(12).trim(), 24]]) {
    const lines = new Markdown(`[${label}](${target})`, 0, 0, theme).render(width);
    if (width === 24) assert.ok(lines.length > 1, `${name}: the label must actually wrap`);
    for (const line of lines) {
      assert.ok(line.includes(openLink), `${name}: every label row must carry the full OSC 8 target under TUIOS`);
    }
  }
  console.log(`PASS ${name}: linked labels and wrapped label rows retain their targets under TUIOS`);
}
