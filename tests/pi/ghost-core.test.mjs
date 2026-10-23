import test from 'node:test';
import assert from 'node:assert/strict';
import { GhostEngine, proseQuery, maskCode, paintGhost, parseSnapshot } from '../../dotfiles/pi/extensions/ghost-core.ts';

const q = (s, line = s.split('\n').length - 1, col = s.split('\n')[line].length) => proseQuery(s.split('\n'), line, col);
test('prose suffix exposes word and preceding context', () => {
  assert.deepEqual(q('Please refac'), { prefix: 'refac', before: 'Please ' });
});
test('every command, path, identifier and code gate is silent', () => {
  for (const s of ['/refac', '  /model refac', '@refac', './refac', 'foo_refac', 'fooRefac', 'version2refac', 'x=refac', 'x:refac', '{refac', '[refac', '<refac', 'x\\refac', '=> refac', '-> refac', '```ts\nrefac', '~~~\nrefac', '`refac`', '`refac', '<code>refac</code>', '<!-- refac']) assert.equal(q(s), null, s);
  assert.equal(q('refactor', 0, 4), null);
  assert.equal(q('refac other', 0, 5), null);
  assert.equal(q('x'.repeat(1001)), null);
  assert.equal(q('x\n'.repeat(10001) + 'refac'), null);
});
test('closed fences restore prose; masking preserves UTF16 offsets and newlines', () => {
  assert.equal(q('<code>\nrefac'), null);
  assert.equal(q('<div>\n<span>\nrefac'), null);
  assert.ok(q('<div>hidden</div>\nrefac'));
  assert.ok(q('```ts\nconst x = 1\n```\nrefac'));
  const s = '😀 `refactor`\nhi';
  assert.equal(maskCode(s).length, s.length);
  assert.equal(maskCode(s).split('\n').length, 2);
});
test('dictionary cold start, casing, and whole-word competitor', () => {
  const e = new GhostEngine(['refactor', 'the', 'there']);
  assert.equal(e.suggest({ before: '', prefix: 'Refac' })?.suffix, 'tor');
  assert.equal(e.suggest({ before: '', prefix: 'REFAC' })?.suffix, 'TOR');
  assert.equal(e.suggest({ before: '', prefix: 'the' }), null);
});
test('session trigrams choose context rather than alphabetic word order', () => {
  const e = new GhostEngine(['configuration', 'configure']);
  e.observe('Please explain configuration. Please explain configuration. Please explain configuration.');
  e.observe('We should configure. We should configure. We should configure.');
  assert.equal(e.suggest({ before: 'Please explain ', prefix: 'configur' })?.word, 'configuration');
  assert.equal(e.suggest({ before: 'We should ', prefix: 'configur' })?.word, 'configure');
});
test('accepted and rejected feedback changes ranking and survives JSON serialization', () => {
  const e = new GhostEngine(['testing', 'tested']), query = {before: 'Try ', prefix: 'test'};
  const first = e.suggest(query);
  e.feedback(query, first.word, false);
  assert.notEqual(e.suggest(query)?.word, first.word);
  e.feedback(query, 'testing', true);
  const restored = new GhostEngine(['testing', 'tested'], parseSnapshot(JSON.parse(JSON.stringify(e.snapshot()))));
  assert.equal(restored.suggest(query)?.word, 'testing');
  assert.equal(restored.snapshot().feedback['test\u0000testing'], 3);
});
const marker = '\x1b_pi:c\x07', fakeStart = '\x1b_pi:fc\x07', fakeEnd = '\x1b_pi:/fc\x07';
const strip = s => s.replace(/\x1b_[^\x07]*\x07/g, '').replace(/\x1b\[[0-9;]*m/g, '');
const measure = s => Array.from(strip(s)).reduce((n,c) => n + (/\p{Extended_Pictographic}|界/u.test(c) ? 2 : 1), 0);
const truncate = (s, budget) => { let out=''; for (const c of s) { if (measure(out+c)>budget) break; out+=c; } return out; };
test('renderer keeps rails, cursor markers, and width with wide input', () => {
  const line = `│ 😀界 refac${marker}${fakeStart} ${fakeEnd}          │`;
  const painted = paintGhost([line], 'tor', 30, measure, truncate)[0];
  assert.match(strip(painted), /😀界 refactor/);
  assert.ok(painted.endsWith('│'));
  assert.ok(painted.includes(marker));
  assert.equal(measure(painted), measure(line));
});
test('narrow rendering truncates suffix without stealing right border', () => {
  const line = `│ refac${marker}${fakeStart} ${fakeEnd} │`;
  const painted = paintGhost([line], 'toring', measure(line), measure, truncate)[0];
  assert.equal(measure(painted), measure(line));
  assert.ok(painted.endsWith('│'));
});
test('renderer never searches inverse-video controls without a cursor marker', () => {
  const line = '\x1b[7m \x1b[0m untouched';
  assert.deepEqual(paintGhost([line], 'tor', 30, measure, truncate), [line]);
});
test('transcript replay deduplicates the same message identity', () => {
  const e = new GhostEngine(['refactor']);
  e.observe('Please refactor', 'message-1'); e.observe('Please refactor', 'message-1');
  assert.equal(e.snapshot().words.refactor, 1);
});
test('state parsing rejects incomplete snapshots and nonfinite counts', () => {
  assert.throws(() => parseSnapshot({version:1}), /Invalid ghost state/);
  assert.throws(() => parseSnapshot({version:1,words:{hello:NaN},bigrams:{},trigrams:{},feedback:{},seen:[]}), /Invalid ghost state/);
});
test('Object prototype names remain completable after persistence', () => {
  const e = new GhostEngine(['constructor']);
  assert.equal(e.suggest({before:'',prefix:'constr'})?.suffix, 'uctor');
  e.observe('constructor');
  const restored = new GhostEngine(['constructor'], parseSnapshot(JSON.parse(JSON.stringify(e.snapshot()))));
  assert.equal(restored.snapshot().words.constructor, 1);
});
test('confidence threshold suppresses broad dictionary prefixes', () => {
  const e = new GhostEngine(['aa','ab','ac','ad','ae','af','ag']);
  assert.equal(e.suggest({before:'',prefix:'a'}), null);
});
test('state snapshots bound every learned dimension and seen IDs', () => {
  const state = {version:1, words:{}, bigrams:{}, trigrams:{}, feedback:{}, seen:Array.from({length:4100}, (_,i) => String(i))};
  for (const [field, size] of [['words',30001],['bigrams',40001],['trigrams',40001],['feedback',10001]])
    for (let i=0;i<size;i++) state[field][`word${i}`] = i + 1;
  const e = new GhostEngine([], parseSnapshot(state)), saved = e.snapshot();
  assert.equal(Object.keys(saved.words).length,30000);
  assert.equal(Object.keys(saved.bigrams).length,40000);
  assert.equal(Object.keys(saved.trigrams).length,40000);
  assert.equal(Object.keys(saved.feedback).length,10000);
  assert.equal(saved.seen.length,4096);
});
