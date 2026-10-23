import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { openHost } from './capability-host.mjs';

const spec = JSON.parse(await readFile(process.argv[2], 'utf8'));
const host = await openHost(spec), text = result => JSON.stringify(result.content);
try {
  const tools = host.session.getAllTools(), names = tools.map(tool => tool.name);
  for (const name of ['ast_grep_run', 'ast_grep_scan', 'ast_grep_outline', 'ast_grep_debug_query', 'ast_grep_languages', 'fetch_content', 'get_search_content']) assert.ok(names.includes(name), `missing ${name}`);
  for (const name of ['ast_grep_rewrite', 'web_search', 'source_check', 'web_enable']) assert.ok(!names.includes(name), name);
  assert.ok(!Object.hasOwn(tools.find(tool => tool.name === 'ast_grep_scan').parameters.properties, 'config'), 'read-only scan must not advertise a project config override');
  assert.deepEqual(Object.keys(tools.find(tool => tool.name === 'fetch_content').parameters.properties).sort(), ['mode', 'url', 'urls']);
  const initial = await readFile(join(host.cwd, 'canary.ts'), 'utf8');
  assert.match(text(await host.call('ast_grep_run', { pattern: 'console.log($ARG)', lang: 'ts', path: 'canary.ts' })), /STRUCTURAL_CANARY/);
  assert.match(text(await host.call('ast_grep_outline', { path: 'canary.ts', view: 'signatures', items: 'all' })), /answer/);
  const scanOverride = await host.call('fixture_nested', { name: 'ast_grep_scan', args: { config: 'sgconfig.yml', path: 'canary.ts' } });
  assert.equal(scanOverride.details.denied, true);
  assert.match(text(scanOverride), /config.*not.*available|additional propert|unsupported.*config/i);
  const nested = await host.call('fixture_nested', { name: 'ast_grep_rewrite', args: { mode: 'pattern', pattern: 'console.log($ARG)', rewrite: 'console.info($ARG)', path: 'canary.ts', lang: 'ts', apply: true } });
  assert.equal(nested.details.denied, true);
  assert.match(text(await host.call('codemode', { code: 'return await tools.ast_grep_rewrite({mode:"pattern",pattern:"console.log($ARG)",rewrite:"console.info($ARG)",path:"canary.ts",lang:"ts",apply:true});' })), /not|unknown|undefined|available|found/i);
  assert.equal(await readFile(join(host.cwd, 'canary.ts'), 'utf8'), initial);
  assert.equal(process.env.PI_ALLOW_BROWSER_COOKIES, undefined);
  assert.equal(process.env.FEYNMAN_ALLOW_BROWSER_COOKIES, undefined);
  let requests = 0, redirectedRequests = 0;
  const other = createServer((_req, res) => { redirectedRequests++; res.end('forbidden'); });
  await new Promise(resolve => other.listen(0, '127.0.0.1', resolve));
  const origin = createServer((req, res) => {
    requests++;
    if (req.url === '/cross') { res.writeHead(302, { Location: `http://127.0.0.1:${other.address().port}/private` }); return res.end(); }
    if (req.url === '/redirect') { res.writeHead(302, { Location: '/page' }); return res.end(); }
    res.writeHead(200, { 'Content-Type': 'text/html' });
    res.end(`<html><head><title>Fixture</title></head><body><article><h1>FETCHCANARY</h1><p>${'Local documentation, not remote inference. '.repeat(100)}</p></article></body></html>`);
  });
  await new Promise(resolve => origin.listen(0, '127.0.0.1', resolve));
  try {
    const url = `http://127.0.0.1:${origin.address().port}`;
    if (spec.loopback) {
      const result = await host.call('fetch_content', { url: url + '/page', mode: 'readable' });
      assert.match(text(result), /FETCHCANARY/);
      assert.equal(typeof result.details.responseId, 'string');
      assert.match(text(await host.call('get_search_content', { responseId: result.details.responseId, findText: 'FETCHCANARY', limit: 200 })), /FETCHCANARY/);
      assert.match(text(await host.call('fetch_content', { url: url + '/redirect', mode: 'raw' })), /FETCHCANARY/);
      assert.match(text(await host.call('fetch_content', { url: url + '/cross' })), /redirect|origin/i);
      assert.equal(redirectedRequests, 0);
    } else {
      assert.match(text(await host.call('fetch_content', { url: url + '/page' })), /private|blocked|loopback|ssrf|not allowed/i);
      assert.equal(requests, 0);
    }
    const count = requests;
    for (const args of [{ proxy: '' }, { auth: true }, { prompt: 'side inference' }, { model: 'different' }, { mode: 'answer' }, { forceClone: true }, { frames: 1 }]) {
      const result = await host.call('fixture_nested', { name: 'fetch_content', args: { url: url + '/page', ...args } });
      assert.equal(result.details.denied, true, JSON.stringify(args));
    }
    assert.equal(requests, count);
    await host.immutable();
    // A writable parent can replace a managed symlink; refuse changed/missing policy.
    await unlink(join(host.agent, 'web-search.json'));
    await writeFile(join(host.agent, 'web-search.json'), '{}');
    assert.match(text(await host.call('fetch_content', { url: url + '/page' })), /policy|managed/i);
    assert.equal(requests, count);
    await unlink(join(host.agent, 'web-search.json'));
    assert.match(text(await host.call('fetch_content', { url: url + '/page' })), /policy|managed/i);
    assert.equal(requests, count);
  } finally {
    origin.closeAllConnections(); other.closeAllConnections();
    await Promise.all([new Promise(resolve => origin.close(resolve)), new Promise(resolve => other.close(resolve))]);
  }
  console.log(`PASS: actual Pi AST/Code Mode and fetch-only execution, pinned binary/config, restricted arguments, policy tamper refusal (${spec.loopback ? 'test loopback profile' : 'production private-range policy'})`);
} finally { await host.close(); }
