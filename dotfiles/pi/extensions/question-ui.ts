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
  private layout?: { margin: number; inner: number; optionsTop: number; choices: (number | undefined)[]; editorTop: number; editorHeight: number; editorStart: number; editorInset: number; actionsTop: number; actions: { start: number; end: number; focus: "back" | "next" }[] };
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
  private editCustom() {
    this.state.choose(this.state.question.options.length);
    this.state.draft.custom = true;
    this.state.focus = "editor";
    this.optionOffset = undefined;
    this.refresh();
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
      this.pasting = !data.includes("\x1b[201~");
      if (s.focus === "editor") { this.editor.handleInput(data); this.refresh(); }
      return;
    }
    if (matchesKey(data, Key.escape) || matchesKey(data, Key.ctrl("c"))) { this.cancel(); return; }
    if ((s.focus === "options" || s.focus === "editor") && s.question.options.length && (matchesKey(data, Key.up) || matchesKey(data, Key.down))) {
      s.focus = "options";
      s.move(matchesKey(data, Key.up) ? -1 : 1);
      this.optionOffset = undefined;
      this.refresh(); return;
    }
    if (matchesKey(data, Key.tab) || matchesKey(data, Key.shift("tab"))) {
      s.tab(matchesKey(data, Key.shift("tab"))); this.refresh(); return;
    }
    if (s.focus === "editor") { this.editor.handleInput(data); this.refresh(); return; }
    if (matchesKey(data, Key.enter)) {
      if (s.focus === "options" && s.draft.cursor === s.question.options.length) this.editCustom();
      else if (s.focus === "back") this.activate("back");
      else this.submit();
      return;
    }
    if (s.focus !== "options") return;
    if (matchesKey(data, Key.pageUp) || matchesKey(data, Key.pageDown)) {
      this.optionOffset = Math.max(0, this.optionStart + (matchesKey(data, Key.pageUp) ? -1 : 1) * Math.max(1, this.optionPage - 1));
      this.refresh(); return;
    }
    const printable = decodeKittyPrintable(data) ?? data;
    if (printable === " " && s.question.multiple) { s.toggle(); this.refresh(); return; }
    if (/^[1-9]$/.test(printable) && Number(printable) <= s.question.options.length + 1) {
      this.optionOffset = undefined;
      s.choose(Number(printable) - 1);
      if (s.question.multiple) s.toggle();
      this.refresh();
    }
  }
  handleMouse(event: TuiMouseEvent) {
    const l = this.layout;
    if (!this.active || !l || event.x < l.margin || event.x >= l.margin + l.inner) return;
    if (event.y >= l.editorTop && event.y < l.editorTop + l.editorHeight && event.x >= l.margin + l.editorInset) {
      if (event.type === "click" && event.button === "left") this.editCustom();
      const result = this.editor.handleMouse({ ...event, x: event.x - l.margin - l.editorInset, y: event.y - l.editorTop + l.editorStart + 1, width: Math.max(1, l.inner - l.editorInset) });
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
    if (choice === this.state.question.options.length) this.editCustom();
    else {
      this.state.focus = "options"; this.state.choose(choice);
      if (this.state.question.multiple) this.state.toggle();
      this.refresh();
    }
    return { handled: true, focus: true, render: true };
  }
  render(width: number): string[] {
    if (width < 1) return [];
    const s = this.state, q = s.question, t = this.theme;
    const margin = width >= 8 ? 2 : 0;
    const inner = Math.max(1, Math.min(100, width - margin));
    const height = Math.max(1, this.tui.terminal.rows - 3);
    const spacious = height >= 9;
    const fill = (rows: string[]) => rows.map(line => paint(keepForeground((margin ? t.fg("accent", "┃ ") : "") + truncateToWidth(line, inner), t.getFgAnsi("text")), width, t.getBgAnsi("customMessageBg")));
    const wrap = (text: string) => wrapTextWithAnsi(text, inner);
    const capped = (rows: string[], n: number) => rows.length <= n ? rows : [...rows.slice(0, Math.max(0, n - 1)), truncateToWidth(rows[n - 1] + "…", inner)];
    const heading = spacious ? [...capped(wrap(t.fg("muted", `Questions${s.questions.length > 1 ? ` · ${q.header} · ${s.index + 1} of ${s.questions.length}` : ""}`)), 2), ""] : [];
    const fullPrompt = wrap(t.bold(q.question));
    const prompt = height >= 3 ? [...capped(fullPrompt, spacious ? Math.max(1, Math.min(3, Math.floor(height / 5))) : 1), ...(spacious ? [""] : [])] : [];
    const editing = s.focus === "editor";
    const help = height >= 2 ? capped(wrap(t.fg("dim", `↑↓ select  ${q.multiple ? "Space toggle  " : ""}Enter ${s.index < s.questions.length - 1 ? "Next" : "submit"}${editing ? "  Shift+Enter newline" : ""}  Esc dismiss`)), spacious ? 2 : 1) : [];
    const buttons: { name: string; focus: "back" | "next" }[] = spacious && s.questions.length > 1 ? [...(s.index > 0 ? [{ name: "Back", focus: "back" as const }] : []), { name: s.index < s.questions.length - 1 ? "Next" : "Submit answer", focus: "next" }] : [];
    const buttonText = buttons.map(({ name, focus }) => t.fg(s.focus === focus ? "accent" : "muted", `[${s.focus === focus ? "> " : ""}${name}]`));
    const actions = buttonText.length ? capped(wrap(buttonText.join("  ")), 1) : [];
    let column = 0;
    const actionBounds = buttons.map((item, index) => {
      const start = column; column += visibleWidth(buttonText[index]);
      const end = Math.min(inner, column); column += 2;
      return { start, end, focus: item.focus };
    }).filter(item => item.start < inner);
    const optionBudget = Math.max(1, height - heading.length - prompt.length - help.length - actions.length - (spacious ? 1 : 0));
    const options: string[] = [];
    const optionIndices: (number | undefined)[] = [];
    let activeStart = 0;
    q.options.forEach((option, i) => {
      const before = options.length;
      if (i === s.draft.cursor) activeStart = before;
      const focused = s.focus === "options" && i === s.draft.cursor;
      const recommended = /\s*\(Recommended\)\s*$/i.test(option.label);
      const title = recommended ? option.label.replace(/\s*\(Recommended\)\s*$/i, "") : option.label;
      const prefix = `${q.multiple ? s.draft.selected.has(i) ? "☑ " : "☐ " : ""}${i + 1}. `;
      options.push(...wrap(t.fg(focused ? "accent" : "text", prefix + title) + (recommended ? t.fg("accent", " (Recommended)") : "")));
      if (option.description) options.push(...wrap(t.fg("muted", " ".repeat(visibleWidth(prefix)) + option.description)));
      optionIndices.push(...Array(options.length - before).fill(i));
    });
    const customStart = options.length;
    const prefix = `${q.options.length + 1}. `;
    const editorInset = Math.min(visibleWidth(prefix), Math.max(0, inner - 1));
    const native: string[] = this.editor.render(Math.max(1, inner - editorInset)).slice(1, -1);
    const cursor = native.findIndex(line => line.includes(CURSOR_MARKER));
    if (cursor >= 0 && inner - editorInset === 1) native[cursor] = CURSOR_MARKER + " ";
    const editBudget = Math.min(4, optionBudget);
    const editStart = Math.max(0, (cursor < 0 ? 0 : cursor) - editBudget + 1);
    const body = editing || this.editor.getExpandedText() ? native.slice(editStart, editStart + editBudget) : [t.fg("muted", "Type your own answer")];
    body.forEach((line, i) => options.push(t.fg(s.draft.cursor === q.options.length ? "accent" : "muted", i === 0 ? truncateToWidth(prefix, editorInset, "") : " ".repeat(editorInset)) + line));
    optionIndices.push(...Array(body.length).fill(q.options.length));
    if (s.draft.cursor === q.options.length) activeStart = customStart + Math.max(0, cursor - editStart - optionBudget + 1);
    if (spacious && fullPrompt.length > prompt.length - 1) {
      options.push(...wrap(t.fg("muted", "Full question")), ...fullPrompt);
    }
    const start = Math.min(this.optionOffset ?? activeStart, Math.max(0, options.length - optionBudget));
    this.optionStart = start;
    this.optionPage = optionBudget;
    const visible = options.slice(start, start + optionBudget);
    const optionsTop = heading.length + prompt.length;
    const editorFirst = Math.max(start, customStart);
    const editorEnd = Math.min(start + visible.length, customStart + body.length);
    this.layout = { margin, inner, optionsTop, choices: optionIndices.slice(start, start + visible.length), editorTop: optionsTop + editorFirst - start, editorHeight: Math.max(0, editorEnd - editorFirst), editorStart: editStart + editorFirst - customStart, editorInset, actionsTop: optionsTop + visible.length + (spacious ? 1 : 0) + help.length, actions: actionBounds };
    return fill([...heading, ...prompt, ...visible, ...(spacious ? [""] : []), ...help, ...actions].slice(0, height));
  }
}
