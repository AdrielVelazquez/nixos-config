import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, mkdir, writeFile, readFile, stat, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { createRequire } from 'node:module';

const root = process.env.PI_TEST_PACKAGE_DIR;
assert.ok(root, 'PI_TEST_PACKAGE_DIR must name the real Pi installation');
const requirePi = createRequire(join(root, 'package.json'));
const jiti = requirePi('jiti').createJiti(import.meta.url, { alias: {
  '@earendil-works/pi-coding-agent': join(root, 'dist/index.js'),
  '@earendil-works/pi-tui': requirePi.resolve('@earendil-works/pi-tui'),
} });
const { createGhostText } = await jiti.import('../../dotfiles/pi/extensions/ghost-text.ts');
const plain = value => value.replace(/\x1b_[^\x07]*\x07/g, '').replace(/\x1b\[[0-9;]*m/g, '');
async function fixture({missing = false, corrupt = false, mode = 'tui', words = 'configuration\n', encoding = 'utf8', files = {}, seed} = {}) {
  const dir = await mkdtemp(join(tmpdir(), 'pi-ghost-unit-'));
  process.env.PI_CODING_AGENT_DIR = dir;
  const wordList = join(dir,'words');
  if (!missing) await writeFile(wordList, words, encoding);
  if (corrupt) await writeFile(join(dir,'ghost-text-state.json'), '{broken');
  for (const [name, content] of Object.entries(files)) { await mkdir(dirname(join(dir,name)), {recursive:true}); await writeFile(join(dir,name), content); }
  const events = new Map(), notices = [];
  let factory, text = 'configurat', focused = true, popup = false;
  const editor = {
    get focused() { return focused; },
    getCursor: () => ({line:0,col:text.length}), getLines: () => [text],
    insertTextAtCursor: value => { text += value; },
    isShowingAutocomplete: () => popup,
    render: width => [text+'\x1b_pi:c\x07\x1b_pi:fc\x07 \x1b_pi:/fc\x07'+' '.repeat(width-text.length-1)],
    handleInput: value => { text += value; }, invalidate() {},
  };
  const originalRender = editor.render, originalInput = editor.handleInput;
  const originalFactory = () => editor;
  factory = originalFactory;
  const ctx = {hasUI:mode === 'tui', mode, sessionManager:{getBranch:() => []}, ui:{
    notify: message => notices.push(message), theme:{fg:(_token,value) => value},
    getEditorComponent: () => factory, setEditorComponent: value => {factory=value;},
  }};
  createGhostText({on:(name,handler) => events.set(name,handler)}, {wordList, seed: seed && {...seed, shellHistory: seed.shellHistory.map(path => join(dir,path))}});
  await events.get('session_start')({},ctx);
  const mount = async () => { await events.get('resources_discover')({},ctx); return factory({requestRender(){}}, {}, {}); };
  return {dir, events, ctx, notices, mount, editor, originalRender, originalInput, originalFactory,
    get factory(){return factory;}, get text(){return text;}, set text(value){text=value;},
    set focused(value){focused=value;}, set popup(value){popup=value;},
    async close(){await events.get('session_shutdown')({},ctx); await rm(dir,{recursive:true,force:true});},
  };
}
test('missing word list disables decoration with one visible notice across new sessions', async () => {
  const f = await fixture({missing:true});
  try {
    await f.events.get('session_start')({}, f.ctx);
    await f.events.get('resources_discover')({}, f.ctx);
    assert.equal(f.factory, f.originalFactory);
    assert.equal(f.notices.length,1);
    assert.match(f.notices[0], /word list/i);
  } finally {await f.close();}
});
test('corrupt state is ignored; new state is atomic and private mode 0600', async () => {
  const f = await fixture({corrupt:true});
  try {
    const editor = await f.mount();
    assert.match(plain(editor.render(80)[0]), /configuration/);
    editor.handleInput('\t');
    assert.equal(f.text, 'configuration ');
    await f.events.get('session_shutdown')({}, f.ctx);
    const statePath = join(f.dir,'ghost-text-state.json');
    assert.equal((await stat(statePath)).mode & 0o777,0o600);
    assert.equal(JSON.parse(await readFile(statePath,'utf8')).words.configuration,1);
    assert.equal(f.notices.length,1);
  } finally {await f.close();}
});
test('same-instance decoration needs no getText; native popup and focus take precedence', async () => {
  const f = await fixture();
  try {
    const editor = await f.mount();
    assert.equal(editor,f.editor);
    f.popup=true; assert.doesNotMatch(plain(editor.render(80)[0]),/configuration/);
    f.popup=false; f.focused=false; assert.doesNotMatch(plain(editor.render(80)[0]),/configuration/);
    f.focused=true; assert.match(plain(editor.render(80)[0]),/configuration/);
    editor.handleInput('\x1b[C'); assert.equal(f.text,'configuration');
  } finally {await f.close();}
});
test('resources discovery is idempotent and shutdown restores editor methods and factory', async () => {
  const f = await fixture();
  try {
    await f.mount(); const factory = f.factory, render = f.editor.render;
    await f.events.get('resources_discover')({},f.ctx);
    assert.equal(f.factory,factory); assert.equal(f.editor.render,render);
    await f.events.get('session_shutdown')({},f.ctx);
    assert.equal(f.factory,f.originalFactory);
    assert.equal(f.editor.render,f.originalRender); assert.equal(f.editor.handleInput,f.originalInput);
  } finally {await f.close();}
});
test('typing through a matching suffix does not teach rejection; divergent typing does', async () => {
  const f = await fixture();
  try {
    const editor = await f.mount(); editor.render(80); editor.handleInput('i');
    editor.render(80); editor.handleInput('x');
    await f.events.get('session_shutdown')({},f.ctx);
    const state = JSON.parse(await readFile(join(f.dir,'ghost-text-state.json'),'utf8'));
    assert.equal(state.feedback['configurat\u0000configuration'],undefined);
    assert.ok(state.feedback['configurati\u0000configuration'] < 0);
  } finally {await f.close();}
});
test('history seeding runs after startup, is persisted and finishes before shutdown completes', async () => {
  const f = await fixture({
    files: {
      'sessions/proj/2026-10-23T10-00-00-000Z_aaaa.jsonl': JSON.stringify({type:'message',message:{role:'user',content:'Restart headroomx now. Then headroomx again.'}}) + '\n',
      history: ': 1:0;kubectl get pods\n'.repeat(3),
    },
    seed: {piSessions:true, ompSessions:null, shellHistory:['history']},
  });
  try {
    await f.events.get('session_shutdown')({}, f.ctx);
    const state = JSON.parse(await readFile(join(f.dir,'ghost-text-state.json'),'utf8'));
    assert.equal(state.words.headroomx,2);
    assert.ok(state.words.kubectl >= 2, String(state.words.kubectl));
  } finally {await f.close();}
});
test('two sessions sharing an agent directory keep each other\'s learning', async () => {
  const f = await fixture();
  const second = new Map();
  createGhostText({on:(name,handler) => second.set(name,handler)}, {wordList: join(f.dir,'words')});
  try {
    await second.get('session_start')({}, f.ctx);
    const say = (events, text, timestamp) => events.get('message_end')({message:{role:'user', content:text, timestamp}});
    await say(f.events, 'alphaword alphaword alphaword', 1);
    await say(second, 'betaword betaword betaword', 2);
    await f.events.get('session_shutdown')({}, f.ctx);
    await second.get('session_shutdown')({}, f.ctx);
    const state = JSON.parse(await readFile(join(f.dir,'ghost-text-state.json'),'utf8'));
    assert.equal(state.words.alphaword,3);
    assert.equal(state.words.betaword,3);
  } finally {await f.close();}
});
test('non-TUI sessions never read missing dictionary or install editor or write state', async () => {
  const f = await fixture({missing:true,mode:'json'});
  try {
    await f.events.get('resources_discover')({},f.ctx);
    await f.events.get('session_shutdown')({},f.ctx);
    assert.equal(f.notices.length,0); assert.equal(f.factory,f.originalFactory);
    await assert.rejects(stat(join(f.dir,'ghost-text-state.json')), {code:'ENOENT'});
  } finally {await f.close();}
});
test('Latin-1 SCOWL seed preserves accented words instead of silently replacing bytes', async () => {
  const f = await fixture({words:'caféine\n',encoding:'latin1'});
  try {
    f.text='café';
    const editor=await f.mount();
    assert.match(plain(editor.render(80)[0]), /caféine/);
    editor.handleInput('\t');
    assert.equal(f.text,'caféine ');
  } finally {await f.close();}
});
