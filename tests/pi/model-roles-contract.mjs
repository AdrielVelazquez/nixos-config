import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const f = JSON.parse(readFileSync(process.argv[2]));
assert.equal(f.settings.defaultProvider, 'roles'); assert.equal(f.settings.defaultModel, 'auto');
assert.equal(f.settings.defaultThinkingLevel, 'high');
const expectedRoles = { default: 'llm-platform/claude-haiku-5-5:high', plan: 'llm-platform/claude-sonnet-5-5:high', slow: 'llm-platform/claude-sonnet-5-5:xhigh',
  smol: 'llm-platform/gpt-6-luna:low', commit: '@smol', widget: '@smol', tiny: 'llm-platform/gpt-6-luna:low', memory: '@tiny',
  task: 'llm-platform/gpt-6.1-sol:medium', advisor: 'llm-platform/gpt-6.1-sol:high', vision: 'llm-platform/gpt-6.1-sol:high' };
assert.deepEqual(f.options.modelRoles, expectedRoles);
assert.equal(f.options.retry.modelFallback, false);
assert.deepEqual(f.options.retry.fallbackChains, {}); assert.equal(f.options.compactionRole, null);
assert.equal(f.options.planMode.readOnly, false);
const planningInstructions = readFileSync('dotfiles/pi/planning-instructions.md', 'utf8');
assert.equal(f.options.planMode.instructions, planningInstructions);
assert.ok(readFileSync(f.entry, 'utf8').includes(JSON.stringify(planningInstructions)));
assert.equal(f.partialInstructions, 'Explicit planning override.');
assert.match(f.roles.build, /model: llm-platform\/gpt-6.1-sol\nthinking: medium/);
assert.match(f.roles.plan, /model: llm-platform\/claude-sonnet-5-5\nthinking: high/);
assert.match(f.roles.title, /model: llm-platform\/gpt-6-luna\nthinking: low/);
assert.ok(f.settings.extensions.includes(f.entry));
assert.equal(f.partialRoles.default, 'llm-platform/claude-haiku-5-5:high');
assert.equal(f.partialRoles.vision, 'fixture/image:high');
assert.equal(f.partialAgents.build, '@slow'); assert.equal(f.partialAgents.title, '@tiny');
console.log('PASS: generated Nix defaults, partial overrides, forced virtual model and resolved task frontmatter');
