import assert from 'node:assert/strict';
import test from 'node:test';

const { daybreakBluePayload } = await import('../../dotfiles/pi/extensions/openai-daybreak-blue-core.ts');
const alias = { provider: 'openai-codex', id: 'gpt-6-sol-daybreak-blue' };
const ordinary = { provider: 'openai-codex', id: 'gpt-6-sol' };

test('adds access_programs only for the alias on openai-codex', () => {
  const out = daybreakBluePayload(alias, { model: 'gpt-6-sol', input: [] });
  assert.deepEqual(out, { model: 'gpt-6-sol', input: [], access_programs: { cyber: 'daybreak_blue' } });
});

test('leaves ordinary model untouched', () => {
  assert.equal(daybreakBluePayload(ordinary, { model: 'gpt-6-sol' }), undefined);
});

test('leaves other physical models untouched', () => {
  assert.equal(daybreakBluePayload(alias, { model: 'gpt-6-luna' }), undefined);
});

test('ignores other providers', () => {
  assert.equal(daybreakBluePayload({ provider: 'openai', id: 'gpt-6-sol-daybreak-blue' }, { model: 'gpt-6-sol' }), undefined);
});

test('passes non-object payloads through', () => {
  for (const payload of [undefined, null, [], 'x', 3]) {
    assert.equal(daybreakBluePayload(alias, payload), undefined);
  }
});

test('does not mutate the input payload', () => {
  const input = { model: 'gpt-6-sol' };
  daybreakBluePayload(alias, input);
  assert.deepEqual(input, { model: 'gpt-6-sol' });
});
