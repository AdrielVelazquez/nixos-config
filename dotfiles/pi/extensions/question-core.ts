export interface Question {
  header: string;
  question: string;
  multiple?: boolean;
  options: { label: string; description: string }[];
}
export interface Answer {
  question: string;
  answer: string[];
  cancelled?: boolean;
}
export const cancelledAnswers = (questions: Question[]): Answer[] => questions.map(({ question }) => ({ question, answer: [], cancelled: true }));

export class QuestionState {
  index = 0;
  focus: "options" | "editor" | "back" | "next" = "options";
  drafts: { cursor: number; selected: Set<number>; custom: boolean; answer?: string[] }[];
  constructor(readonly questions: Question[]) {
    this.drafts = questions.map(() => ({ cursor: 0, selected: new Set(), custom: false }));
    this.focus = this.question.options.length ? "options" : "editor";
  }
  get question() { return this.questions[this.index]; }
  get draft() { return this.drafts[this.index]; }
  choose(index: number) {
    this.draft.cursor = index;
    if (!this.question.multiple) this.draft.custom = false;
  }
  move(delta: number) {
    this.choose(Math.max(0, Math.min(this.question.options.length - 1, this.draft.cursor + delta)));
  }
  toggle() {
    const { selected, cursor } = this.draft;
    if (this.question.options[cursor]) {
      if (selected.has(cursor)) selected.delete(cursor); else selected.add(cursor);
    }
  }
  tab(reverse = false) {
    const stops = [...(this.question.options.length ? ["options"] : []), "editor", ...(this.index > 0 ? ["back"] : []), "next"] as typeof this.focus[];
    this.focus = stops[(stops.indexOf(this.focus) + (reverse ? stops.length - 1 : 1)) % stops.length];
  }
  back() {
    if (this.index > 0) this.index--;
    this.focus = "next";
  }
  submit(custom: string): Answer[] | undefined {
    const text = custom.trim();
    const q = this.question;
    const customActive = q.multiple || this.draft.custom || this.focus === "editor";
    const chosen = q.multiple
      ? [...this.draft.selected].sort((a, b) => a - b).map(i => q.options[i].label)
      : !customActive && q.options[this.draft.cursor] ? [q.options[this.draft.cursor].label] : [];
    const answer = [...chosen, ...(text && customActive ? [text] : [])];
    if (!answer.length) return;
    this.draft.answer = answer;
    if (this.index < this.questions.length - 1) {
      this.index++;
      this.focus = this.question.options.length ? "options" : "editor";
      return;
    }
    if (this.drafts.some(draft => !draft.answer)) return;
    return this.questions.map(({ question }, i) => ({ question, answer: this.drafts[i].answer! }));
  }
}
