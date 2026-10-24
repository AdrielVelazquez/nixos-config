// Worker for ghost-store.test.mjs: one "Pi session" that learns and commits to a shared state directory.
import { GhostEngine } from '../../dotfiles/pi/extensions/ghost-core.ts';
import { commitState } from '../../dotfiles/pi/extensions/ghost-store.ts';

const [dir, id, rounds] = process.argv.slice(2);
const engine = new GhostEngine(['the\t0.05']);
for (let round = 0; round < Number(rounds); round++) {
  engine.observe('sharedword unique' + 'abcdefgh'[Number(id)]);
  if (!await commitState(engine, dir, 20000)) process.exit(2);
}
