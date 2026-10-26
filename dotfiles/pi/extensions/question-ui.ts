import type { ExtensionContext } from "@earendil-works/pi-coding-agent";
import { CURSOR_MARKER, decodeKittyPrintable, Editor, Key, matchesKey, truncateToWidth, visibleWidth, wrapTextWithAnsi, type TUI, type TuiMouseEvent } from "@earendil-works/pi-tui";
import { keepForeground, paint } from "./opencode-ui-core.ts";
import { QuestionState, type Answer, type Question } from "./question-core.ts";

type Theme = ExtensionContext["ui"]["theme"];

export class QuestionCard {
  readonly state: QuestionState;
  private editors: Editor[];
  private active = true;
  private hasFocus = false;
  private pasting = false;
  private optionOffset: number | undefined;
  private optionStart = 0;
  private optionPage = 1;
  private layout?: { margin: number; inner: number; optionsTop: number; choices: (number | undefined)[]; editorTop: number; editorHeight: number; editorStart: number; actionsTop: number; actions: { start: number; end: number; focus: "back" | "next" }[] };
  constructor(private tui: TUI, private theme: Theme, questions: Question[], private done: (answers: Answer[] | null) => void) {
    this.state = new QuestionState(questions);
    const color = (token: "accent" | "muted" | "dim" | "warning") => (s: string) => theme.fg(token, s);
    this.editors = questions.map((_, index) => {
      const editor = new Editor(tui, {
        borderColor: color("muted"),
        selectList: { selectedPrefix: color("accent"), selectedText: color("accent"), description: color("muted"), scrollInfo: color("dim"), noMatch: color("warning") },
      });
      // Native Editor clears its buffer before onSubmit; restore it for batch Back navigation.
      editor.onSubmit = value => { editor.setText(value); this.submit(value); };
      editor.onChange = () => { this.state.drafts[index].custom = true; this.refresh(); };
      return editor;
    });
  }
  get focused() { return this.hasFocus; }
  set focused(value: boolean) {
    this.hasFocus = value;
    this.syncFocus();
  }
  private get editor() { return this.editors[this.state.index]; }
  private syncFocus() {
    if (this.hasFocus && this.state.focus === "editor") this.state.draft.custom = true;
    this.editors.forEach((editor, i) => { editor.focused = this.hasFocus && this.state.focus === "editor" && i === this.state.index; });
  }
  private refresh() {
    this.syncFocus();
    this.tui.requestRender();
  }
  private finish(answers: Answer[] | null) {
    if (!this.active) return;
    this.active = false;
    this.done(answers);
  }
  cancel() { this.finish(null); }
  private submit(custom = this.editor.getExpandedText()) {
    const index = this.state.index;
    const answers = this.state.submit(custom);
    if (this.state.index !== index) this.optionOffset = undefined;
    if (answers) this.finish(answers);
    else this.refresh();
  }
  private activate(focus: "back" | "next") {
    this.state.focus = focus;
    if (focus === "back") { this.state.back(); this.optionOffset = undefined; this.refresh(); }
    else this.submit();
  }
  invalidate() { this.editors.forEach(editor => editor.invalidate()); }
  dispose() { this.active = false; }
  handleInput(data: string) {
    if (!this.active) return;
    const s = this.state;
    if (this.pasting || data.includes("\x1b[200~")) {
      s.focus = "editor"; this.syncFocus();
      this.pasting = !data.includes("\x1b[201~");
      this.editor.handleInput(data); this.refresh(); return;
    }
    if (matchesKey(data, Key.escape) || matchesKey(data, Key.ctrl("c"))) { this.cancel(); return; }
    if (matchesKey(data, Key.tab) || matchesKey(data, Key.shift("tab"))) {
      s.tab(matchesKey(data, Key.shift("tab"))); this.refresh(); return;
    }
    if (s.focus === "editor") { this.editor.handleInput(data); this.refresh(); return; }
    if (matchesKey(data, Key.enter)) {
      if (s.focus === "back") this.activate("back"); else this.submit();
      return;
    }
    if (s.focus !== "options") return;
    if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.pageDown)) {
      this.optionOffset = Math.max(0, this.optionStart + (matchesKey(data, Key.pageUp) ? -1 : 1) * Math.max(1, this.optionPage - 1));
      this.refresh(); return;
    }
    if (matchesKey(data, Key.up) || matchesKey(data, Key.down)) {
      this.optionOffset = undefined;
      s.move(matchesKey(data, Key.up) ? -1 : 1); this.refresh(); return;
    }
    const printable = decodeKittyPrintable(data) ?? data;
    if (printable === " " && s.question.multiple) { s.toggle(); this.refresh(); return; }
    if (/^[1-9]$/.test(printable) && Number(printable) <= s.question.options.length) {
      this.optionOffset = undefined;
      s.choose(Number(printable) - 1);
      if (s.question.multiple) s.toggle();
      this.refresh(); return;
    }
    if (!printable.startsWith("\x1b") && !/[\x00-\x1f\x7f]/.test(printable)) {
      s.focus = "editor"; this.syncFocus(); this.editor.handleInput(data); this.refresh();
    }
  }
  handleMouse(event: TuiMouseEvent) {
    const l = this.layout;
    if (!this.active || !l || event.x < l.margin || event.x >= l.margin + l.inner) return;
    if (event.y >= l.editorTop && event.y < l.editorTop + l.editorHeight) {
      if (event.type === "click" && event.button === "left") { this.state.focus = "editor"; this.syncFocus(); }
      const result = this.editor.handleMouse({ ...event, x: event.x - l.margin, y: event.y - l.editorTop + l.editorStart + 1, width: l.inner });
      if (result) this.refresh();
      return result;
    }
    if (event.y === l.actionsTop && event.type === "click" && event.button === "left") {
      const action = l.actions.find(action => event.x - l.margin >= action.start && event.x - l.margin < action.end);
      // Closing the card restores the main editor; do not focus this retired component again.
      if (action) { this.activate(action.focus); return { handled: true, focus: this.active, render: true }; }
    }
    const row = event.y - l.optionsTop;
    if (row < 0 || row >= l.choices.length) return;
    if (event.type === "wheel") {
      this.optionOffset = Math.max(0, this.optionStart + (event.wheelDelta ?? 0));
      this.refresh(); return { handled: true, render: true };
    }
    const choice = l.choices[row];
    if (event.type !== "click" || event.button !== "left" || choice === undefined) return;
    this.state.focus = "options"; this.state.choose(choice);
    if (this.state.question.multiple) this.state.toggle();
    this.refresh(); return { handled: true, focus: true, render: true };
  }
  render(width: number): string[] {
    if (width < 1) return [];
    const s = this.state, q = s.question, t = this.theme;
    const margin = width >= 8 ? 2 : 0;
    const inner = Math.max(1, Math.min(100, width - margin));
    const height = Math.max(1, this.tui.terminal.rows - 3);
    const fill = (rows: string[]) => rows.map(line => paint(keepForeground((margin ? t.fg("accent", "┃ ") : "") + truncateToWidth(line, inner), t.getFgAnsi("text")), width, t.getBgAnsi("customMessageBg")));
    const wrap = (text: string) => wrapTextWithAnsi(text, inner);
    const capped = (rows: string[], n: number) => rows.length <= n ? rows : [...rows.slice(0, Math.max(0, n - 1)), truncateToWidth(rows[n - 1] + "…", inner)];
    const heading = capped(wrap(t.fg("accent", `Question · ${q.header} · ${s.index + 1} of ${s.questions.length}`)), 2);
    const fullPrompt = wrap(t.bold(q.question));
    const prompt = capped(fullPrompt, Math.max(1, Math.min(3, Math.floor(height / 5))));
    const help = capped(wrap(t.fg("dim", `${q.multiple ? "Space toggle · " : "Choose one · "}Tab focus · Enter ${s.index < s.questions.length - 1 ? "Next" : "submit"} · Shift+Enter newline · Esc cancel`)), 2);
    const button = (name: string, focus: typeof s.focus) => t.fg(s.focus === focus ? "accent" : "muted", `[${s.focus === focus ? "> " : ""}${name}]`);
    const buttons: { name: string; focus: "back" | "next" }[] = [...(s.index > 0 ? [{ name: "Back", focus: "back" as const }] : []), { name: s.index < s.questions.length - 1 ? "Next" : "Submit answer", focus: "next" }];
    const buttonText = buttons.map(item => button(item.name, item.focus));
    const actions = capped(wrap(buttonText.join("  ")), 1);
    let column = 0;
    const actionBounds = buttons.map((item, index) => {
      const start = column; column += visibleWidth(buttonText[index]);
      const end = Math.min(inner, column); column += 2;
      return { start, end, focus: item.focus };
    }).filter(item => item.start < inner);
    const customActive = q.multiple || s.draft.custom || s.focus === "editor";
    const label = capped(wrap(t.fg(s.focus === "editor" || s.draft.custom ? "accent" : "muted", `Your answer${s.focus === "editor" ? " · editing inline" : ""}${q.multiple ? " (adds to choices)" : customActive ? " (replaces choice)" : this.editor.getExpandedText().trim() ? " (draft; not selected)" : " (optional)"}`)), 1);
    const native = this.editor.render(inner);
    // Keep the native editor's cursor and text layout; only bound its visible viewport to this card's budget.
    const body = native.slice(1, -1);
    if (height < 9) {
      const choice = q.options[s.draft.cursor];
      const option = choice ? t.fg("accent", `${s.draft.cursor + 1}. ${choice.label}`) : undefined;
      const head = height >= 4 ? [t.bold(q.question), ...(height >= 5 && option ? [option] : []), t.fg("muted", "Your answer")] : height >= 3 ? [t.bold(q.question)] : [];
      const budget = Math.max(1, height - head.length - (height >= 2 ? 1 : 0));
      const cursorRow = body.findIndex(line => line.includes(CURSOR_MARKER));
      const start = Math.max(0, (cursorRow < 0 ? body.length - 1 : cursorRow) - budget + 1);
      const input = body.slice(start, start + budget);
      this.layout = { margin, inner, optionsTop: option && height >= 5 ? 1 : -1, choices: option && height >= 5 ? [s.draft.cursor] : [], editorTop: head.length, editorHeight: input.length, editorStart: start, actionsTop: -1, actions: [] };
      return fill([...head, ...input, ...(height >= 2 ? [t.fg("dim", "Enter submit · Esc cancel")] : [])].slice(0, height));
    }
    const editBudget = Math.max(1, Math.min(4, height - heading.length - prompt.length - help.length - actions.length - label.length - 2));
    const cursor = body.findIndex(line => line.includes(CURSOR_MARKER));
    const editStart = Math.max(0, (cursor < 0 ? body.length - 1 : cursor) - editBudget + 1);
    const editorRows = body.slice(editStart, editStart + editBudget);
    const optionBudget = Math.max(1, height - heading.length - prompt.length - help.length - actions.length - label.length - editorRows.length);
    const options: string[] = [];
    const optionIndices: (number | undefined)[] = [];
    let activeStart = 0;
    q.options.forEach((option, i) => {
      const before = options.length;
      if (i === s.draft.cursor) activeStart = options.length;
      const focused = s.focus === "options" && i === s.draft.cursor;
      const recommended = /\s*\(Recommended\)\s*$/i.test(option.label);
      const title = recommended ? option.label.replace(/\s*\(Recommended\)\s*$/i, "") : option.label;
      const marker = q.multiple ? (s.draft.selected.has(i) ? "☑" : "☐") : !s.draft.custom && i === s.draft.cursor ? "●" : "○";
      options.push(...wrap(t.fg(focused ? "accent" : "text", `${marker} ${i + 1}. ${title}`) + (recommended ? t.fg("accent", " [Recommended]") : "")));
      options.push(...wrap(t.fg("muted", `  ${option.description}`)));
      optionIndices.push(...Array(options.length - before).fill(i));
    });
    if (fullPrompt.length > prompt.length) options.push(...wrap(t.fg("accent", "Full question")), ...fullPrompt);
    const start = Math.min(this.optionOffset ?? activeStart, Math.max(0, options.length - optionBudget));
    this.optionStart = start;
    this.optionPage = optionBudget;
    const visible = options.slice(start, start + optionBudget);
    if (start + optionBudget < options.length && visible.length > 1) visible[visible.length - 1] = t.fg("dim", "↓ more · PgUp/PgDn scroll");
    const choices = visible.map((_, i) => optionIndices[start + i]);
    if (start + optionBudget < options.length && visible.length > 1) choices[choices.length - 1] = undefined;
    const optionsTop = heading.length + prompt.length;
    this.layout = { margin, inner, optionsTop, choices, editorTop: optionsTop + visible.length + label.length, editorHeight: editorRows.length, editorStart: editStart, actionsTop: optionsTop + visible.length + label.length + editorRows.length + help.length, actions: actionBounds };
    const rows = [...heading, ...prompt, ...visible, ...label, ...editorRows, ...help, ...actions];
    return fill(rows.slice(0, height));
  }
}
