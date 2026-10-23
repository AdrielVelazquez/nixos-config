import { readFile, mkdir, writeFile, rename, unlink } from 'node:fs/promises';
import { join } from 'node:path';
import { createHash, randomUUID } from 'node:crypto';
import type { AgentMessage } from '@earendil-works/pi-agent-core';
import { CustomEditor, getAgentDir, type ExtensionAPI, type ExtensionContext, type KeybindingsManager } from '@earendil-works/pi-coding-agent';
import { matchesKey, visibleWidth, truncateToWidth, type EditorComponent, type EditorTheme, type TUI } from '@earendil-works/pi-tui';
import { GhostEngine, proseQuery, paintGhost, parseSnapshot, type Snapshot, type Suggestion, type Query } from './ghost-core.ts';
import { seedEngine, type SeedOptions } from './ghost-seed.ts';

type Factory = (tui: TUI, theme: EditorTheme, keys: KeybindingsManager) => EditorComponent;
type CursorEditor = EditorComponent & { focused: boolean; getCursor(): { line: number; col: number }; getLines(): string[]; insertTextAtCursor(text: string): void; isShowingAutocomplete?(): boolean };
type Displayed = Suggestion & { query: Query; key: string };
function supportsGhost(editor: EditorComponent): editor is CursorEditor {
  return 'focused' in editor && 'getCursor' in editor && typeof editor.getCursor === 'function' && 'getLines' in editor && typeof editor.getLines === 'function' && typeof editor.insertTextAtCursor === 'function';
}

/** Deterministic local word completion; the current visual editor keeps ownership. */
export function createGhostText(pi: ExtensionAPI, { wordList, seed }: { wordList: string; seed?: SeedOptions }): void {
  const dir = getAgentDir(), statePath = join(dir, 'ghost-text-state.json');
  let engine: GhostEngine | undefined, initialized = false;
  let seeding: Promise<void> | undefined, stopSeeding = false;
  let saveTimer: NodeJS.Timeout | undefined, saveChain = Promise.resolve();
  let context: ExtensionContext | undefined;
  const warnings = new Set<string>();
  const mounts = new Map<Factory, { previous: Factory | undefined; ctx: ExtensionContext }>();
  const decorated = new Map<CursorEditor, { render: CursorEditor['render']; input: CursorEditor['handleInput'] }>();
  const warn = (key: string, message: string) => {
    if (!warnings.has(key)) { warnings.add(key); context?.ui.notify(message, 'warning'); }
  };
  const save = (): Promise<void> => {
    if (!engine) return saveChain;
    const data = JSON.stringify(engine.snapshot());
    saveChain = saveChain.then(async () => {
      await mkdir(dir, { recursive: true, mode: 0o700 });
      const temp = statePath + '.' + randomUUID() + '.tmp';
      try {
        await writeFile(temp, data, { mode: 0o600, flag: 'wx' });
        await rename(temp, statePath);
      } finally { await unlink(temp).catch(error => { if (error.code !== 'ENOENT') throw error; }); }
    }).catch((error: unknown) => warn('save', 'Ghost text state could not be saved: ' + String(error)));
    return saveChain;
  };
  const scheduleSave = () => {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(() => { void save(); }, 500);
    saveTimer.unref();
  };
  const learn = (message: AgentMessage) => {
    if (!engine || (message.role !== 'user' && message.role !== 'assistant')) return;
    const text = typeof message.content === 'string' ? message.content : message.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
    const id = createHash('sha256').update(JSON.stringify([message.role, message.timestamp, text])).digest('hex');
    engine.observe(text, id); scheduleSave();
  };
  const install = (ctx: ExtensionContext) => {
    if (!engine || !ctx.hasUI || ctx.mode !== 'tui' || process.env.PI_SUBAGENT_CHILD === '1') return;
    const previous = ctx.ui.getEditorComponent();
    if (previous && mounts.has(previous)) return;
    const factory: Factory = (tui, theme, keybindings) => {
      const editor = previous ? previous(tui, theme, keybindings) : new CustomEditor(tui, theme, keybindings);
      if (!supportsGhost(editor)) {
        warn('editor', 'Ghost text requires an editor exposing focus, cursor, lines and insertion.');
        return editor;
      }
      if (decorated.has(editor)) return editor;
      const render = editor.render, input = editor.handleInput;
      decorated.set(editor, { render, input });
      let dismissed = '', shown: Displayed | null = null;
      let snapshotKey = '', cached: Suggestion | null = null;
      const suggestion = (): Displayed | null => {
        const cursor = editor.getCursor(), lines = editor.getLines();
        if (!editor.focused || editor.isShowingAutocomplete?.()) return null;
        const query = proseQuery(lines, cursor.line, cursor.col);
        if (!query) return null;
        const key = JSON.stringify([lines, cursor.line, cursor.col]);
        if (key === dismissed) return null;
        if (key !== snapshotKey) { snapshotKey = key; cached = engine!.suggest(query); }
        return cached ? { query, key, ...cached } : null;
      };
      editor.render = (width: number) => {
        const lines = render.call(editor, width), next = suggestion();
        const painted = next ? paintGhost(lines, next.suffix, width, visibleWidth, truncateToWidth, text => ctx.ui.theme.fg('dim', text)) : lines;
        shown = painted !== lines ? next : null;
        return painted;
      };
      editor.handleInput = (data: string) => {
        const next = suggestion();
        if (next && shown?.key === next.key && (matchesKey(data, 'tab') || matchesKey(data, 'right'))) {
          engine!.feedback(next.query, next.word, true); scheduleSave();
          shown = null; cached = null; snapshotKey = '';
          editor.insertTextAtCursor(next.suffix + (matchesKey(data, 'tab') ? ' ' : ''));
          tui.requestRender(); return;
        }
        if (next && shown?.key === next.key && matchesKey(data, 'escape')) {
          engine!.feedback(next.query, next.word, false); scheduleSave();
          dismissed = next.key; shown = null; tui.requestRender(); return;
        }
        if (next && shown?.key === next.key && !data.startsWith('\x1b') && !/[\x00-\x1f\x7f]/.test(data) && !next.suffix.startsWith(data)) {
          engine!.feedback(next.query, next.word, false); scheduleSave();
        }
        const before = editor.getLines().join('\n');
        input.call(editor, data);
        if (editor.getLines().join('\n') !== before) dismissed = '';
        shown = null;
      };
      return editor;
    };
    mounts.set(factory, { previous, ctx });
    ctx.ui.setEditorComponent(factory);
  };
  pi.on('session_start', async (_event, ctx) => {
    if (!ctx.hasUI || ctx.mode !== 'tui' || process.env.PI_SUBAGENT_CHILD === '1') return;
    context = ctx;
    if (!initialized) {
      initialized = true;
      let words: string[], state: Snapshot | undefined;
      try {
        const bytes = await readFile(wordList);
        let text: string;
        try { text = new TextDecoder('utf-8', { fatal: true }).decode(bytes); }
        catch { text = bytes.toString('latin1'); } // SCOWL wamerican.35 is ISO-8859-1.
        words = text.split(/\r?\n/);
      }
      catch (error: unknown) { warn('dictionary', 'Ghost text cannot read word list: ' + String(error)); return; }
      try { state = parseSnapshot(JSON.parse(await readFile(statePath, 'utf8'))); }
      catch (error: unknown) {
        if (!(error instanceof Error && 'code' in error && error.code === 'ENOENT')) warn('state', 'Ignoring unreadable ghost text state: ' + String(error));
      }
      engine = new GhostEngine(words, state);
    }
    for (const entry of ctx.sessionManager.getBranch()) if (entry.type === 'message') learn(entry.message);
    if (engine && seed && !seeding) {
      // History seeding runs in the background and never delays the editor.
      seeding = seedEngine(engine, seed, join(dir, 'sessions'), ctx.sessionManager.getSessionFile?.(), () => stopSeeding)
        .then(changed => { if (changed) scheduleSave(); })
        .catch((error: unknown) => warn('seed', 'Ghost text history seeding failed: ' + String(error)));
    }
  });
  // Pi awaits resource discovery after visual owners' session_start handlers.
  pi.on('resources_discover', (_event, ctx) => { install(ctx); });
  pi.on('message_end', event => { learn(event.message); });
  pi.on('session_shutdown', async () => {
    clearTimeout(saveTimer);
    for (const [editor, original] of decorated) { editor.render = original.render; editor.handleInput = original.input; }
    decorated.clear();
    for (const [factory, { previous, ctx }] of mounts) if (ctx.ui.getEditorComponent() === factory) ctx.ui.setEditorComponent(previous);
    mounts.clear();
    if (seeding) {
      // A running seed gets a short grace period, then stops at its next chunk; offsets keep what it learned.
      const grace = setTimeout(() => { stopSeeding = true; }, 250);
      await seeding;
      clearTimeout(grace);
      seeding = undefined; stopSeeding = false;
    }
    clearTimeout(saveTimer);
    await save();
  });
}

/** Standalone lab entry; managed installations pass an immutable Nix option. */
export default function ghostText(pi: ExtensionAPI): void {
  createGhostText(pi, { wordList: process.env.PI_GHOST_WORDLIST ?? '' });
}
