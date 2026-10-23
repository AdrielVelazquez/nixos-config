import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const root = process.env.LSP_PACKAGE_ROOT;
test('packaged push-only diagnostics use the fresh diagnostic path', () => {
  assert.ok(root, 'LSP_PACKAGE_ROOT points to the built pinned package');
  const source = readFileSync(join(root, 'src/pi-lsp-extension.ts'), 'utf8');
  assert.match(source, /push-only servers need no diagnosticProvider/);
  assert.match(source, /isSupportedBy: \(\) => true/);
  assert.doesNotMatch(source, /client\.hasCapability\(DocumentDiagnosticRequest\.method\)/);
});
test('the vendored dependency closure has no lifecycle scripts', () => {
  assert.ok(root, 'LSP_PACKAGE_ROOT points to the built pinned package');
  function visit(directory) {
    for (const item of readdirSync(directory, { withFileTypes: true })) {
      if (!item.isDirectory() || item.name.startsWith('.')) continue;
      const child = join(directory, item.name);
      if (item.name.startsWith('@')) { visit(child); continue; }
      const metadata = JSON.parse(readFileSync(join(child, 'package.json')));
      for (const hook of ['preinstall', 'install', 'postinstall', 'prepare']) assert.equal(metadata.scripts?.[hook], undefined, `${metadata.name}: ${hook}`);
      try { visit(join(child, 'node_modules')); } catch (error) { if (error.code !== 'ENOENT') throw error; }
    }
  }
  visit(join(root, '../..'));
});
