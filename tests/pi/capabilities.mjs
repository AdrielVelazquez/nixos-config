import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { readFile, unlink, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { openHost } from './capability-host.mjs';

const spec = JSON.parse(await readFile(process.argv[2], 'utf8'));
const host = await openHost(spec), text = result => JSON.stringify(result.content);
try {
  const tools = host.session.getAllTools(), names = tools.map(tool => tool.name);
  for (const name of ['ast_grep_run', 'ast_grep_scan', 'ast_grep_outline', 'ast_grep_debug_query', 'ast_grep_languages', 'fetch_content', 'get_search_content', 'web_search']) assert.ok(names.includes(name), `missing ${name}`);
  for (const name of ['ast_grep_rewrite', 'source_check', 'web_enable']) assert.ok(!names.includes(name), name);
  assert.ok(!Object.hasOwn(tools.find(tool => tool.name === 'ast_grep_scan').parameters.properties, 'config'), 'read-only scan must not advertise a project config override');
  assert.deepEqual(Object.keys(tools.find(tool => tool.name === 'fetch_content').parameters.properties).sort(), ['mode', 'url', 'urls']);
  assert.deepEqual(Object.keys(tools.find(tool => tool.name === 'web_search').parameters.properties).sort(), ['category', 'domainFilter', 'numResults', 'queries', 'query', 'recencyFilter']);
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
  const searchRequests = [];
  const exa = createServer(async (req, res) => {
    let raw = ''; for await (const part of req) raw += part;
    searchRequests.push({ method: req.method, url: req.url, key: req.headers['x-api-key'], body: raw ? JSON.parse(raw) : null });
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ results: [{ title: 'Search fixture', url: 'https://example.com/fixture', highlights: ['SEARCHCANARY'] }] }));
  });
  await new Promise(resolve => exa.listen(0, '127.0.0.1', resolve));
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
    if (spec.loopback) {
      // Production has no key in the store and uses Exa's hosted MCP. The loopback profile drives the real
      // provider code against a synthetic Exa-compatible API, using an environment-only synthetic credential.
      process.env.EXA_API_KEY = 'synthetic-only'; process.env.EXA_BASE_URL = `http://127.0.0.1:${exa.address().port}`;
      const searched = await host.call('web_search', { query: 'SEARCHQUERY', numResults: 3, recencyFilter: 'week', domainFilter: ['example.com'] });
      assert.match(text(searched), /SEARCHCANARY/);
      const searchId = searched.content.map(part => part.text ?? '').join('').match(/responseId "([^"]+)"/)?.[1];
      assert.equal(typeof searchId, 'string', 'search must store retrievable results');
      assert.match(text(await host.call('get_search_content', { responseId: searchId, queryIndex: 0, findText: 'SEARCHCANARY', limit: 200 })), /SEARCHCANARY/);
      assert.equal(searchRequests.length, 1, 'one provider request per search');
      const sent = searchRequests[0];
      assert.equal(sent.url, '/search'); assert.equal(sent.key, 'synthetic-only');
      assert.equal(sent.body.query, 'SEARCHQUERY'); assert.equal(sent.body.numResults, 3);
      assert.deepEqual(sent.body.includeDomains, ['example.com']);
      assert.ok(!('contents' in sent.body && sent.body.contents.text), 'search must not request full page text');
    }
    const searchCount = searchRequests.length;
    for (const args of [{ provider: 'brave' }, { provider: ['exa', 'brave'] }, { workflow: 'summary-review' }, { workflow: 'auto-summary' }, { proxy: '' }, { proxy: 'http://127.0.0.1:1' }, { includeContent: true }, { model: 'different' }, { queries: ['a', 'b', 'c', 'd', 'e'] }, { query: 'x'.repeat(401) }]) {
      const result = await host.call('fixture_nested', { name: 'web_search', args: { query: 'denied', ...args } });
      assert.equal(result.details.denied, true, JSON.stringify(args));
    }
    assert.equal(searchRequests.length, searchCount, 'denied search arguments must not reach the provider');
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
    assert.match(text(await host.call('web_search', { query: 'SEARCHQUERY' })), /policy|managed/i);
    assert.equal(requests, count);
    await unlink(join(host.agent, 'web-search.json'));
    assert.match(text(await host.call('fetch_content', { url: url + '/page' })), /policy|managed/i);
    assert.match(text(await host.call('web_search', { query: 'SEARCHQUERY' })), /policy|managed/i);
    assert.equal(requests, count);
    assert.equal(searchRequests.length, searchCount, 'tampered or missing policy must not reach the search provider');
  } finally {
    origin.closeAllConnections(); other.closeAllConnections(); exa.closeAllConnections();
    await Promise.all([new Promise(resolve => origin.close(resolve)), new Promise(resolve => other.close(resolve)), new Promise(resolve => exa.close(resolve))]);
  }
  console.log(`PASS: actual Pi AST/Code Mode, fetch and Exa-only search execution, pinned binary/config, restricted arguments, policy tamper refusal (${spec.loopback ? 'test loopback profile' : 'production private-range policy'})`);
} finally { await host.close(); }
