export type Query = { before: string; prefix: string };
export type Suggestion = { suffix: string; word: string; confidence: number };
export type Snapshot = { version: 1; words: Record<string, number>; bigrams: Record<string, number>; trigrams: Record<string, number>; feedback: Record<string, number>; seen: string[] };

/** Validate persisted state at the JSON boundary. */
export function parseSnapshot(value: unknown): Snapshot {
  if (!value || typeof value !== 'object' || !('version' in value) || value.version !== 1) throw new Error('Unknown ghost state version');
  const records: Record<string, Record<string, number>> = {};
  for (const field of ['words', 'bigrams', 'trigrams', 'feedback']) {
    const record = Reflect.get(value, field);
    if (!record || typeof record !== 'object' || Array.isArray(record) || Object.values(record).some(n => typeof n !== 'number' || !Number.isFinite(n))) throw new Error('Invalid ghost state ' + field);
    records[field] = record;
  }
  const seen = Reflect.get(value, 'seen');
  if (!Array.isArray(seen) || seen.some(s => typeof s !== 'string')) throw new Error('Invalid ghost state seen IDs');
  return { version: 1, words: records.words, bigrams: records.bigrams, trigrams: records.trigrams, feedback: records.feedback, seen: seen.slice(-4096) };
}

const voidTags: Record<string, true> = { area: true, base: true, br: true, col: true, embed: true, hr: true, img: true, input: true, link: true, meta: true, param: true, source: true, track: true, wbr: true };

/** Length-preserving Markdown code mask, including unfinished code spans. */
export function maskCode(text: string): string {
  const chars = text.split('');
  const hide = (a: number, b: number) => { for (let i = a; i < b; i++) if (chars[i] !== '\n') chars[i] = ' '; };
  let fence = '', fenceLength = 0, offset = 0;
  for (const line of text.split('\n')) {
    const match = /^( {0,3})(`{3,}|~{3,})/.exec(line);
    if (fence) {
      hide(offset, offset + line.length);
      if (match && match[2][0] === fence && match[2].length >= fenceLength && !line.slice(match[0].length).trim()) fence = '';
    } else if (match) {
      fence = match[2][0]; fenceLength = match[2].length; hide(offset, offset + line.length);
    }
    offset += line.length + 1;
  }
  const source = chars.join('');
  const constructs = /(`+)([\s\S]*?)(\1|$)|<!--[\s\S]*?(?:-->|$)/g;
  for (const match of source.matchAll(constructs)) hide(match.index!, match.index! + match[0].length);
  const stack: { name: string; start: number }[] = [];
  for (const tag of chars.join('').matchAll(/<(\/?)([A-Za-z][\w:-]*)(?:\s[^<>]*?)?(\/?)>/g)) {
    const name = tag[2].toLowerCase(), end = tag.index! + tag[0].length;
    hide(tag.index!, end);
    if (tag[1]) {
      const opener = stack.findLastIndex(item => item.name === name);
      if (opener >= 0) { hide(stack[opener].start, end); stack.length = opener; }
    } else if (!tag[3] && !Object.hasOwn(voidTags, name)) stack.push({ name, start: tag.index! });
  }
  if (stack.length) hide(stack[0].start, text.length);
  return chars.join('');
}

/** Omp prose/token caps plus conservative two-character and end-of-line gates. */
export function proseQuery(lines: readonly string[], lineIndex: number, col: number): Query | null {
  const line = lines[lineIndex];
  if (line === undefined || col !== line.length || line.length > 1000) return null;
  const text = lines.join('\n');
  if (text.length > 20000 || line.trimStart().startsWith('/') || line.startsWith('->') || line.startsWith('=>')) return null;
  const match = /[\p{L}\p{M}']+$/u.exec(line);
  if (!match || [...match[0]].length < 2) return null;
  const token = /\S+$/u.exec(line)?.[0] ?? '';
  if (/[\\/@_=:{}\[\]<>\d]/u.test(token) || /\p{Ll}\p{Lu}/u.test(token)) return null;
  const start = text.length - lines.slice(lineIndex + 1).reduce((n, l) => n + l.length + 1, 0) - line.length + match.index;
  if (!maskCode(text).slice(start, start + match[0].length).trim()) return null;
  let before = text.slice(0, start).slice(-2000);
  if (/^[\uDC00-\uDFFF]/.test(before)) before = before.slice(1);
  return { before, prefix: match[0] };
}

const VOCABULARY_WORD = /^[\p{L}\p{M}']{2,64}$/u;
/** Pseudo-counts that one unit of web frequency is worth against typed counts. omp uses 10000; 1000 fit typed prose best. */
const PRIOR_STRENGTH = 1000;
/** Web weight of vocabulary words without a measured frequency: dictionary-only words and tool names. */
const UNSEEN_WEIGHT = 1e-9;
/** Share of the probability mass under a prefix the best extension needs; omp's default is 0.15, 0.3 trades coverage for accuracy. */
const CONFIDENCE_THRESHOLD = 0.3;
/** A word outside the vocabulary must have been typed this often before it may be suggested. */
const MIN_TYPED_UNKNOWN = 2;

type Lexicon = { words: string[]; weights: Float64Array };
type Grouped = Map<string, Map<string, number>>;

/** Parse `word` or `word<TAB>web-frequency` lines into a sorted, unique, lowercase lexicon. */
function parseLexicon(lines: readonly string[]): Lexicon {
  const words: string[] = [], weights: number[] = [];
  let ordered = true;
  for (const line of lines) {
    const tab = line.indexOf('\t');
    const raw = tab < 0 ? line : line.slice(0, tab);
    if (!VOCABULARY_WORD.test(raw)) continue;
    const word = raw.toLowerCase(), weight = tab < 0 ? 0 : Number(line.slice(tab + 1));
    if (words.length && !(words[words.length - 1] < word)) ordered = false;
    words.push(word); weights.push(Number.isFinite(weight) && weight > 0 ? weight : 0);
  }
  if (ordered) return { words, weights: Float64Array.from(weights) };
  const merged = new Map<string, number>();
  words.forEach((word, i) => merged.set(word, Math.max(merged.get(word) ?? 0, weights[i])));
  const sorted = [...merged.keys()].sort();
  return { words: sorted, weights: Float64Array.from(sorted, word => merged.get(word)!) };
}

function lowerBound(sorted: readonly string[], prefix: string): number {
  let lo = 0, hi = sorted.length;
  while (lo < hi) { const mid = (lo + hi) >>> 1; if (sorted[mid] < prefix) lo = mid + 1; else hi = mid; }
  return lo;
}

/** Group `head\0word` counts as head -> word -> count, so a query never rebuilds keys per candidate. */
function group(record: Record<string, number>): Grouped {
  const groups: Grouped = new Map();
  for (const [key, count] of Object.entries(record)) {
    const cut = key.lastIndexOf('\u0000'), head = key.slice(0, cut);
    let words = groups.get(head);
    if (!words) groups.set(head, words = new Map());
    words.set(key.slice(cut + 1), count);
  }
  return groups;
}

/** Web-frequency prior blended with typed unigram/bigram/trigram counts; no model or subprocess. */
export class GhostEngine {
  private lexicon: Lexicon;
  private state: Snapshot;
  private typedOnly: string[] | undefined;
  private grouped: { bigrams: Grouped; trigrams: Grouped; feedback: Grouped } | undefined;
  constructor(lexicon: readonly string[], state?: Snapshot) {
    this.lexicon = parseLexicon(lexicon);
    this.state = state ?? { version: 1, words: {}, bigrams: {}, trigrams: {}, feedback: {}, seen: [] };
    for (const field of ['words', 'bigrams', 'trigrams', 'feedback'] as const) Object.setPrototypeOf(this.state[field], null);
    this.snapshot();
  }
  private known(word: string): boolean {
    return this.lexicon.words[lowerBound(this.lexicon.words, word)] === word;
  }
  /** Typed words missing from the lexicon, sorted for prefix search. */
  private typedOutsideLexicon(): string[] {
    return this.typedOnly ??= Object.keys(this.state.words).filter(word => !this.known(word)).sort();
  }
  private contexts() {
    return this.grouped ??= { bigrams: group(this.state.bigrams), trigrams: group(this.state.trigrams), feedback: group(this.state.feedback) };
  }
  observe(text: string, id?: string): void {
    if (id && this.state.seen.includes(id)) return;
    if (id) { this.state.seen.push(id); if (this.state.seen.length > 4096) this.state.seen.shift(); }
    const masked = maskCode(text.slice(0, 20000));
    let previous = '', penultimate = '';
    for (const match of masked.matchAll(/[\p{L}\p{M}']+/gu)) {
      const word = match[0].toLowerCase();
      const left = masked.slice(0, match.index!), right = masked.slice(match.index! + match[0].length);
      const token = (/\S*$/u.exec(left)?.[0] ?? '') + match[0] + (/^\S*/u.exec(right)?.[0] ?? '');
      if (word.length > 64 || /[\\/@_=:{}\[\]<>\d]/u.test(token) || /\p{Ll}\p{Lu}/u.test(token)) { previous = ''; penultimate = ''; continue; }
      this.state.words[word] = (this.state.words[word] ?? 0) + 1;
      if (previous) { const k = previous + '\u0000' + word; this.state.bigrams[k] = (this.state.bigrams[k] ?? 0) + 1; }
      if (penultimate) { const k = penultimate + '\u0000' + previous + '\u0000' + word; this.state.trigrams[k] = (this.state.trigrams[k] ?? 0) + 1; }
      penultimate = previous; previous = word;
    }
    this.typedOnly = undefined; this.grouped = undefined;
  }
  suggest(query: Query): Suggestion | null {
    const prefix = query.prefix.toLowerCase(), { words, weights } = this.lexicon, typed = this.state.words;
    const context = maskCode(query.before).toLowerCase().match(/[\p{L}\p{M}']+/gu) ?? [];
    const prev = context.at(-1) ?? '', pen = context.at(-2) ?? '';
    const { bigrams, trigrams, feedback } = this.contexts();
    const afterPrev = bigrams.get(prev), afterPair = trigrams.get(pen + '\u0000' + prev), bias = feedback.get(prefix);
    let best = '', bestScore = -1, total = 0;
    // Every word under the prefix, the finished prefix itself included, shares the probability mass.
    const consider = (word: string, prior: number) => {
      const score = (prior + (typed[word] ?? 0) + 4 * (afterPrev?.get(word) ?? 0) + 16 * (afterPair?.get(word) ?? 0)) * Math.exp(Math.max(-6, Math.min(6, bias?.get(word) ?? 0)));
      total += score;
      if (word !== prefix && (score > bestScore || (score === bestScore && word.length < best.length))) { best = word; bestScore = score; }
    };
    for (let i = lowerBound(words, prefix); i < words.length && words[i].startsWith(prefix); i++)
      consider(words[i], PRIOR_STRENGTH * (weights[i] > 0 ? weights[i] : UNSEEN_WEIGHT));
    const outside = this.typedOutsideLexicon();
    for (let i = lowerBound(outside, prefix); i < outside.length && outside[i].startsWith(prefix); i++)
      if (typed[outside[i]] >= MIN_TYPED_UNKNOWN) consider(outside[i], 0);
    if (!best || bestScore / total < CONFIDENCE_THRESHOLD) return null;
    let suffix = best.slice(prefix.length);
    if (query.prefix === query.prefix.toUpperCase()) suffix = suffix.toUpperCase();
    return { suffix, word: best, confidence: bestScore / total };
  }
  feedback(query: Query, word: string, accepted: boolean): void {
    const key = query.prefix.toLowerCase() + '\u0000' + word.toLowerCase();
    this.state.feedback[key] = Math.max(-6, Math.min(6, (this.state.feedback[key] ?? 0) + (accepted ? 3 : -2)));
    this.grouped = undefined;
    if (accepted) this.observe(query.before + word);
  }
  snapshot(): Snapshot {
    for (const [field, limit] of [['words', 30000], ['bigrams', 40000], ['trigrams', 40000], ['feedback', 10000]] as const) {
      const entries = Object.entries(this.state[field]);
      if (entries.length > limit) {
        this.state[field] = Object.setPrototypeOf(Object.fromEntries(entries.sort((a, b) => Math.abs(b[1]) - Math.abs(a[1])).slice(0, limit)), null);
        this.typedOnly = undefined; this.grouped = undefined;
      }
    }
    this.state.seen = this.state.seen.slice(-4096);
    return this.state;
  }
}

/** Paint only cursor padding, never a visual owner's right rail or footer. */
export function paintGhost(lines: string[], suffix: string, width: number, measure: (s: string) => number, truncate: (s: string, n: number, e: string) => string, dim: (s: string) => string = s => '\x1b[38;2;128;128;128m' + s + '\x1b[39m'): string[] {
  const marker = '\x1b_pi:c\x07', fakeStart = '\x1b_pi:fc\x07', fakeEnd = '\x1b_pi:/fc\x07';
  for (let i = 0; i < lines.length; i++) {
    const at = lines[i].indexOf(marker); if (at < 0) continue;
    const cursor = at + marker.length;
    let end = cursor, style = '';
    if (lines[i].startsWith(fakeStart + ' ' + fakeEnd, cursor)) { end = cursor + fakeStart.length + 1 + fakeEnd.length; style = 'fake'; }
    else if (lines[i].startsWith('\x1b[7m \x1b[0m', cursor)) { end = cursor + '\x1b[7m \x1b[0m'.length; style = 'inverse'; }
    else if (lines[i][cursor] === ' ') { end = cursor + 1; style = 'hardware'; }
    else return lines;
    const padding = /^ */.exec(lines[i].slice(end))![0].length;
    const available = Math.min(1 + padding, width - measure(lines[i].slice(0, at)));
    const shown = truncate(suffix, Math.max(0, available), ''); if (!shown) return lines;
    const first = [...new Intl.Segmenter().segment(shown)][0].segment;
    const head = style === 'fake' ? fakeStart + first + fakeEnd : style === 'inverse' ? '\x1b[7m' + first + '\x1b[0m' : first;
    const result = [...lines];
    result[i] = lines[i].slice(0, cursor) + head + dim(shown.slice(first.length)) + lines[i].slice(end + Math.max(0, measure(shown) - 1));
    return result;
  }
  return lines;
}
