import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';

const [packageRoot, fixture] = process.argv.slice(2);
const { parseFrontmatter, parseFrontmatterList } = await import(pathToFileURL(`${packageRoot}/src/agents/frontmatter.js`).href);
const { roles } = JSON.parse(await readFile(fixture, 'utf8'));
const expected = { plan: ['llm-platform/claude-sonnet-5-5', 'xhigh'], build: ['llm-platform/gpt-6.1-sol', 'high'],
  scout: ['llm-platform/gpt-6.1-sol', 'low'], explore: ['llm-platform/gpt-6-luna', 'low'], title: ['llm-platform/gpt-6-luna', 'off'] };
for (const [name, [model, thinking]] of Object.entries(expected)) {
  const { frontmatter } = parseFrontmatter(roles[name]);
  assert.equal(frontmatter.name, name);
  assert.equal(frontmatter.model, model);
  assert.equal(frontmatter.thinking, thinking);
  assert.equal(frontmatter.inheritGlobalContext, 'true');
  const tools = parseFrontmatterList(frontmatter.tools);
  assert.ok(tools.includes('mcp:headroom/headroom_stats'));
  if (['scout', 'explore'].includes(name)) {
    assert.ok(tools.includes('ast_grep_run'));
    assert.ok(!tools.includes('ast_grep_rewrite'));
    assert.equal(tools.includes('fetch_content'), name === 'scout');
    for (const denied of ['bash', 'edit', 'write', 'subagent']) assert.ok(!tools.includes(denied), `${name} exposed ${denied}`);
    assert.equal(frontmatter.allowNestedSubagents, 'false');
  }
}
console.log('PASS: actual package parser consumes all Nix role models/thinking, inheritance and read-only tool ceilings');
