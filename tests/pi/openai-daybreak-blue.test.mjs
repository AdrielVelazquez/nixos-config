import assert from 'node:assert/strict';
import test from 'node:test';

const { default: extension } = await import('../../dotfiles/pi/extensions/openai-daybreak-blue.ts');

const physical = { provider: 'openai-codex', id: 'gpt-6-sol' };
const models = [];
const handlers = new Map();
extension({
  registerVirtualModel: (model) => models.push(model),
  on: (event, handler) => handlers.set(event, handler),
});
const [model] = models;
const registry = (found) => ({ modelRegistry: { find: (provider, id) => (found && provider === 'openai-codex' && id === 'gpt-6-sol' ? found : undefined) } });

test('registers the Daybreak Blue alias on openai-codex with the catalog limits', () => {
  assert.equal(models.length, 1);
  assert.equal(model.provider, 'openai-codex');
  assert.equal(model.id, 'gpt-6-sol-daybreak-blue');
  assert.equal(model.name, 'GPT-6 Sol (Daybreak Blue)');
  assert.equal(model.contextWindow, 272000);
  assert.equal(model.maxTokens, 128000);
  assert.deepEqual(model.thinkingLevels, ['off', 'minimal', 'low', 'medium', 'high', 'xhigh', 'max']);
});

test('route returns the physical gpt-6-sol model with the requested thinking level', () => {
  assert.deepEqual(model.route({ thinkingLevel: 'high' }, registry(physical)), { model: physical, thinkingLevel: 'high' });
});

test('route throws when the physical model is missing', () => {
  assert.throws(() => model.route({ thinkingLevel: 'high' }, registry(undefined)), /openai-codex\/gpt-6-sol is unavailable/);
});

test('before_provider_request adds the field only for the alias', () => {
  const hook = handlers.get('before_provider_request');
  const payload = { model: 'gpt-6-sol', input: [] };
  assert.deepEqual(hook({ payload }, { model: { provider: 'openai-codex', id: 'gpt-6-sol-daybreak-blue' } }), {
    model: 'gpt-6-sol',
    input: [],
    access_programs: { cyber: 'daybreak_blue' },
  });
  assert.equal(hook({ payload }, { model: { provider: 'openai-codex', id: 'gpt-6-sol' } }), undefined);
});
