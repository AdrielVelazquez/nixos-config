import assert from 'node:assert/strict';
import { test } from 'node:test';
import { access, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.PI_TEST_PACKAGE_DIR;
const theme = await import(pathToFileURL(`${root}/dist/modes/interactive/theme/theme.js`));
const { validateThemeJson } = await import(pathToFileURL(`${root}/dist/modes/interactive/theme/theme-schema.js`));
theme.setThemeJsonValidator(validateThemeJson);
for (const [name, text] of [['opencode', '238;238;238'], ['cyberdream', '255;255;255']]) {
  test(`themes_are_strict_schema_valid: ${name}`, async () => {
    const file = resolve(`dotfiles/pi/themes/${name}.json`);
    await access(file);
    const loaded = theme.loadThemeFromPath(file, 'truecolor');
    assert.equal(loaded.name, name);
    assert.match(loaded.fg('text', 'prose'), new RegExp(`\\x1b\\[38;2;${text}mprose`));
    const json = JSON.parse(await readFile(file, 'utf8'));
    assert.equal(json.appearance, 'dark');
  });
}

test('Cyberdream keeps Neovim palette colours and explicit shaded panels', async () => {
  const json = JSON.parse(await readFile(resolve('dotfiles/pi/themes/cyberdream.json'), 'utf8'));
  assert.deepEqual(Object.fromEntries(['fg', 'grey', 'blue', 'green', 'cyan', 'red', 'purple', 'bg', 'bg_alt', 'bg_highlight'].map((key) => [key, json.vars[key]])), {
    fg: '#ffffff', grey: '#7b8496', blue: '#5ea1ff', green: '#5eff6c', cyan: '#5ef1ff', red: '#ff6e5e', purple: '#bd5eff', bg: '#16181a', bg_alt: '#1e2124', bg_highlight: '#3c4048',
  });
  assert.equal(json.colors.text, 'fg');
  assert.equal(json.colors.muted, 'grey');
  assert.equal(json.colors.userMessageBg, 'bg_alt');
  assert.equal(json.colors.toolSuccessBg, 'bg_alt');
  assert.equal(json.colors.thinkingMedium, 'cyan');
  const loaded = theme.loadThemeFromPath(resolve('dotfiles/pi/themes/cyberdream.json'), 'truecolor');
  assert.match(loaded.fg('muted', 'footer'), /\x1b\[38;2;123;132;150mfooter/);
});
