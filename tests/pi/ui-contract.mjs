import assert from 'node:assert/strict';
import { test } from 'node:test';
import { access, readFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { pathToFileURL } from 'node:url';

const root = process.env.PI_TEST_PACKAGE_DIR;
const theme = await import(pathToFileURL(`${root}/dist/modes/interactive/theme/theme.js`));
const { validateThemeJson } = await import(pathToFileURL(`${root}/dist/modes/interactive/theme/theme-schema.js`));
theme.setThemeJsonValidator(validateThemeJson);
for (const [name, text] of [['omp-reference', '201;198;188'], ['omp-dark', '201;198;188'], ['opencode', '238;238;238']]) {
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
