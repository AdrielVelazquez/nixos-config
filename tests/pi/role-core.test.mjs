import { test } from 'node:test';
import assert from 'node:assert/strict';
import { chooseRoute, fallbackRoutes, fallbackSelectors, mergeConfig, parseSelector, resolveRole, resolveSelector, roleNames, retryable, agentFrontmatter } from '../../dotfiles/pi/extensions/role-core.ts';
const models = [
  { provider: 'fixture', id: 'primary', input: ['text'], reasoning: true },
  { provider: 'fixture', id: 'small', input: ['text'], reasoning: true },
  { provider: 'fixture', id: 'vision', input: ['text', 'image'], reasoning: true },
  { provider: 'backup', id: 'primary', input: ['text'], reasoning: true },
];
const config = { modelRoles: { default: 'fixture/primary:high', smol: 'fixture/small:low', slow: 'fixture/primary:xhigh', plan: '@slow', tiny: 'fixture/small:off', vision: 'fixture/vision:medium', custom: '@smol:high' }, retry: { modelFallback: true, cooldownMs: 100, fallbackChains: { default: ['fixture/small:low'] } } };
const user = { reason: 'user', thinkingLevel: 'medium', messages: [{ role: 'user', content: 'hello' }] };
test('exact nested model and suffix grammar', () => {
  assert.deepEqual(parseSelector('openrouter/anthropic/claude:high'), { reference: 'openrouter/anthropic/claude', thinking: 'high' });
  for (const selector of ['luna', 'fixture/primary:auto', 'fixture/primary:']) assert.throws(() => parseSelector(selector));
});
test('aliases preserve effort and referring suffix wins', () => {
  assert.equal(resolveRole('plan', config, models).thinkingLevel, 'xhigh');
  assert.equal(resolveRole('custom', config, models).thinkingLevel, 'high');
  assert.equal(resolveSelector('@smol:inherit', config, models, 'medium').thinkingLevel, 'low');
});
test('cycles fail explicitly', () => assert.throws(() => resolveRole('a', { modelRoles: { a: '@b', b: '@a' } }, models), /cycle/));
test('availability alternatives are not fallback chains', () => {
  const c = { modelRoles: { default: 'missing/nope,fixture/small:low' } };
  assert.equal(resolveRole('default', c, models).model.id, 'small');
  assert.deepEqual(fallbackSelectors(c, 'default', models[1]), []);
});
test('null clears a selector and empty chain stops inheritance without mutating defaults', () => {
  const c = mergeConfig(config, { modelRoles: { smol: null }, retry: { fallbackChains: { default: [] } } });
  assert.equal(resolveRole('smol', c, models).model.id, 'primary');
  assert.deepEqual(c.retry.fallbackChains.default, []);
  assert.equal(config.modelRoles.smol, 'fixture/small:low');
});
test('direct compaction sticks to previous physical model and thinking', () => {
  const previous = { model: models[0], thinkingLevel: 'high' };
  const r = chooseRoute(config, { ...user, reason: 'direct', previous }, models, 'smol');
  assert.equal(r.model.id, 'primary'); assert.equal(r.thinkingLevel, 'high');
  assert.equal(chooseRoute(config, { ...user, reason: 'direct' }, models).model.id, 'primary');
});
test('compactionRole opts in; explicit auxiliary consumer still wins', () => {
  const c = { ...config, compactionRole: 'smol' };
  assert.equal(chooseRoute(c, { ...user, reason: 'direct', previous: { model: models[0] } }, models).model.id, 'small');
  assert.equal(chooseRoute(c, { ...user, reason: 'direct' }, models, 'default', 'tiny').thinkingLevel, 'off');
});
test('plan, slow keyword and custom role route real consumers', () => {
  assert.equal(chooseRoute(config, user, models, 'plan').role, 'plan');
  assert.equal(chooseRoute(config, { ...user, messages: [{ role: 'user', content: 'ultrathink' }] }, models).role, 'slow');
  assert.equal(chooseRoute(config, user, models, 'custom').model.id, 'small');
});
test('image capability required, never silently strips image', () => {
  const request = { ...user, messages: [{ role: 'user', content: [{ type: 'image' }] }] };
  assert.equal(chooseRoute(config, request, models).model.id, 'vision');
  assert.throws(() => chooseRoute({ modelRoles: { default: 'fixture/primary' } }, request, models), /image-capable/);
});
test('continuation preserves physical route', () => assert.equal(chooseRoute(config, { ...user, reason: 'continuation', previous: { model: models[1], thinkingLevel: 'low' } }, models).model.id, 'small'));
test('chain specificity exact, provider, role, default', () => {
  const c = mergeConfig(config, { retry: { fallbackChains: { smol: ['fixture/vision'], 'fixture/*': ['backup/*'], 'fixture/primary': [] } } });
  assert.deepEqual(fallbackSelectors(c, 'smol', models[0]), []);
  assert.deepEqual(fallbackSelectors(c, 'smol', models[1]), ['backup/*']);
  assert.deepEqual(fallbackSelectors(config, 'smol', models[1]), ['fixture/small:low']);
});
test('provider wildcard preserves model and effort', () => {
  const c = mergeConfig(config, { retry: { fallbackChains: { default: ['backup/*'] } } });
  const [r] = fallbackRoutes(c, 'default', { model: models[0], thinkingLevel: 'high' }, models);
  assert.equal(r.model.provider, 'backup'); assert.equal(r.model.id, 'primary'); assert.equal(r.thinkingLevel, 'high');
});
test('429 falls back, cooldown holds, expiry restores', () => {
  const first = chooseRoute(config, user, models, 'default', undefined, 1000);
  const next = chooseRoute(config, { ...user, reason: 'retry', state: first.state, failed: { ...first, message: { errorMessage: '429 rate limit' } } }, models, 'default', undefined, 1000);
  assert.equal(next.model.id, 'small');
  assert.equal(chooseRoute(config, { ...user, state: next.state }, models, 'default', undefined, 1050).model.id, 'small');
  assert.equal(chooseRoute(config, { ...user, state: next.state }, models, 'default', undefined, 1101).model.id, 'primary');
  assert.throws(() => chooseRoute(config, { ...user, reason: 'retry', state: next.state, failed: { ...next, message: { errorMessage: '429' } } }, models), /exhausted/);
});
test('fallback is empty and disabled by default', () => {
  const c = { modelRoles: config.modelRoles };
  assert.deepEqual(fallbackSelectors(c, 'default', models[0]), []);
  assert.equal(chooseRoute(c, { ...user, reason: 'retry', failed: { model: models[0], message: { errorMessage: '429' } } }, models).model.id, 'primary');
});
test('eligible failures exclude authentication even mixed with retryable tokens', () => {
  for (const error of ['overloaded_error', 'quota exhausted', 'context_length_exceeded', '503']) assert.equal(retryable(error), true);
  for (const error of ['401 unauthorized', '403 quota exhausted', 'invalid API key: 429', 'authentication_error overloaded', 'permission_denied quota', 'authorization_error quota exhausted', 'API key missing: rate limit']) {
    assert.equal(retryable(error), false, error);
    assert.equal(chooseRoute(config, { ...user, reason: 'retry', failed: { model: models[0], message: { errorMessage: error } } }, models).model.id, 'primary');
  }
});
test('only consumable builtins and declared custom roles are listed', () => {
  assert.ok(roleNames(config).includes('custom'));
  assert.ok(!roleNames({ modelTags: { judge: {} }, cycleOrder: ['speech'] }).includes('judge'));
  assert.ok(!roleNames({ cycleOrder: ['speech'] }).includes('speech'));
});
test('task frontmatter resolves per-agent selector or task default', () => {
  const c = mergeConfig(config, { modelRoles: { task: '@smol' }, task: { agentModelOverrides: { reviewer: 'fixture/primary:xhigh' } }, agents: { reviewer: { description: 'Review', prompt: 'Review.', tools: ['read'] }, worker: { description: 'Build', prompt: 'Build.' } } });
  assert.match(agentFrontmatter(c, 'reviewer', models), /model: "fixture\/primary"\nthinking: xhigh/);
  assert.match(agentFrontmatter(c, 'worker', models), /model: "fixture\/small"\nthinking: low/);
});
