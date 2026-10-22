import assert from 'node:assert/strict';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';
const [packageRoot, fixture] = process.argv.slice(2);
const { requiredEntry } = JSON.parse(await readFile(fixture, 'utf8'));
const sdk = await import(pathToFileURL(`${process.env.PI_TEST_PACKAGE_DIR}/dist/index.js`).href);
const api = await import(pathToFileURL(`${packageRoot}/src/shared/required-child-extensions.js`).href);
const dir = await mkdtemp(join(tmpdir(), 'pi-required-'));
try {
  const loaded = await sdk.discoverAndLoadExtensions([requiredEntry], dir, dir);
  assert.deepEqual(loaded.errors, []);
  const extension = loaded.extensions[0], ctx = { sessionManager: { getSessionId: () => 'required-fixture' } };
  for (const handler of extension.handlers.get('session_start')) await handler({ reason: 'startup' }, ctx);
  const snapshot = api.resolveRequiredChildExtensions('required-fixture');
  assert.ok(snapshot.length >= 1);
  assert.equal(snapshot[0].id, 'managed-policy');
  assert.ok(snapshot.every(entry => entry.requireForAllRunners));
  assert.throws(() => api.assertRequiredChildExtensionsAdmitted([snapshot], { agent: 'scout', runnerType: 'external-cli' }), /host requires child extensions/);
  for (const handler of extension.handlers.get('session_shutdown')) await handler({}, ctx);
  assert.deepEqual(api.resolveRequiredChildExtensions('required-fixture'), []);
  console.log('PASS: Nix-generated required policy loads via real Pi, rejects external runners and disposes native registration');
} finally { await rm(dir, { recursive: true, force: true }); }
