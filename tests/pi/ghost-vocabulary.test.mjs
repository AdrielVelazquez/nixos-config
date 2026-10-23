import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { GhostEngine } from '../../dotfiles/pi/extensions/ghost-core.ts';

const path = process.env.PI_GHOST_VOCABULARY;
assert.ok(path, 'PI_GHOST_VOCABULARY must name the generated default vocabulary');
const engine = () => new GhostEngine(readFileSync(path, 'utf8').split('\n'));

test('default vocabulary completes a tool name that no English dictionary carries', () => {
  assert.equal(engine().suggest({ before: '', prefix: 'kubec' })?.word, 'kubectl');
});
test('default vocabulary picks the most common word under a two-letter prefix', () => {
  assert.equal(engine().suggest({ before: '', prefix: 'th' })?.word, 'the');
});
test('default vocabulary does not extend a finished, very common word', () => {
  assert.equal(engine().suggest({ before: '', prefix: 'the' }), null);
});
