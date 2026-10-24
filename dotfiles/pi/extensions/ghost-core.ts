export type Query = { before: string; prefix: string };
export type Suggestion = { suffix: string; word: string; confidence: number };
export type Snapshot = { version: 1; words: Record<string, number>; bigrams: Record<string, number>; trigrams: Record<string, number>; feedback: Record<string, number>; seen: string[]; sources?: Record<string, number>; rev?: number };

/** True when every value is a finite number; a loop, because this runs over every entry on every shared save. */
function finiteCounts(record: object): boolean {
  for (const key in record) { const n = Reflect.get(record, key); if (typeof n !== 'number' || !Number.isFinite(n)) return false; }
  return true;
}

/** Validate persisted state at the JSON boundary. */
export function parseSnapshot(value: unknown): State {
  if (!value || typeof value !== 'object' || !('version' in value) || value.version !== 1) throw new Error('Unknown ghost state version');
  const records: Record<string, Record<string, number>> = {};
  for (const field of ['words', 'bigrams', 'trigrams', 'feedback', 'sources']) {
    const record = Reflect.get(value, field) ?? (field === 'sources' ? {} : undefined);
    if (!record || typeof record !== 'object' || Array.isArray(record) || !finiteCounts(record)) throw new Error('Invalid ghost state ' + field);
    records[field] = Object.setPrototypeOf(record, null);
  }
  const seen = Reflect.get(value, 'seen');
  if (!Array.isArray(seen) || seen.some(s => typeof s !== 'string')) throw new Error('Invalid ghost state seen IDs');
  const rev = Reflect.get(value, 'rev') ?? 0;
  if (typeof rev !== 'number' || !Number.isFinite(rev)) throw new Error('Invalid ghost state revision');
  return { version: 1, words: records.words, bigrams: records.bigrams, trigrams: records.trigrams, feedback: records.feedback, seen: seen.slice(-4096), sources: records.sources, rev };
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
/** Feedback only nudges the ranking: a rejection can lower a word to e^-1 of its mass but never hide the dominant word of a prefix (typing past a suggestion is usually a different word, not a wrong ranking). */
const FEEDBACK_ACCEPT = 3, FEEDBACK_REJECT = 0.25, FEEDBACK_FLOOR = -1, FEEDBACK_CEILING = 3;
const clampFeedback = (value: number) => Math.max(FEEDBACK_FLOOR, Math.min(FEEDBACK_CEILING, value));
/** Shell commands are seeded only when used habitually (a one-off is usually a typo) and only when the web prior ranks the word below this weight (common English words need no help). */
const MIN_COMMAND_USES = 3, MAX_COMMAND_COUNT = 6, COMMON_WEB_WEIGHT = 1e-6;
const MAX_SOURCES = 5000;
/** Bounds of the learned state; the least-used entries are dropped first when one is exceeded. */
const LIMITS = { words: 30000, bigrams: 40000, trigrams: 40000, feedback: 10000 } as const;

type Lexicon = { words: string[]; weights: Float64Array };
type Grouped = Map<string, Map<string, number>>;
type Counts = Record<string, number>;
/** The persisted state plus the bookkeeping merging needs; `rev` counts commits to the shared file. */
export type State = Snapshot & { sources: Counts; rev: number };
/** What one session learned since it last committed. Additive, so concurrent sessions merge by adding. */
export type Delta = { words: Counts; bigrams: Counts; trigrams: Counts; feedback: Counts; floors: Counts; sources: Counts; seen: string[] };

const counts = (): Counts => Object.setPrototypeOf({}, null);
const emptyDelta = (): Delta => ({ words: counts(), bigrams: counts(), trigrams: counts(), feedback: counts(), floors: counts(), sources: counts(), seen: [] });
const bump = (record: Counts, key: string, by = 1) => { record[key] = (record[key] ?? 0) + by; };
export const isEmptyDelta = (delta: Delta) => delta.seen.length === 0 && [delta.words, delta.bigrams, delta.trigrams, delta.feedback, delta.floors, delta.sources].every(record => Object.keys(record).length === 0);

/** Fold an older delta into a newer one (a failed write puts its delta back). */
function addDelta(target: Delta, older: Delta): void {
  for (const field of ['words', 'bigrams', 'trigrams', 'feedback'] as const) for (const key in older[field]) bump(target[field], key, older[field][key]);
  for (const key in older.floors) target.floors[key] = Math.max(target.floors[key] ?? 0, older.floors[key]);
  for (const key in older.sources) target.sources[key] ??= older.sources[key];
  target.seen.unshift(...older.seen);
}

/** Trim a state to its limits in place; true when something was dropped. */
function bound(state: State): boolean {
  let trimmed = false;
  for (const field of ['words', 'bigrams', 'trigrams', 'feedback'] as const) {
    // Counting keys is cheap; entries are only materialised for the rare trim.
    if (Object.keys(state[field]).length > LIMITS[field]) {
      state[field] = Object.setPrototypeOf(Object.fromEntries(Object.entries(state[field]).sort((a, b) => Math.abs(b[1]) - Math.abs(a[1])).slice(0, LIMITS[field])), null);
      trimmed = true;
    }
  }
  if (Object.keys(state.sources).length > MAX_SOURCES) { state.sources = Object.setPrototypeOf(Object.fromEntries(Object.entries(state.sources).slice(-MAX_SOURCES)), null); trimmed = true; }
  state.seen = state.seen.slice(-4096);
  return trimmed;
}

/** Apply one session's delta to a state in place (the caller owns it): counts and feedback add, command floors take the maximum, fingerprints are replaced and seen ids are unioned. */
export function applyDelta(state: State, delta: Delta): State {
  for (const field of ['words', 'bigrams', 'trigrams'] as const) for (const key in delta[field]) bump(state[field], key, delta[field][key]);
  for (const key in delta.feedback) state.feedback[key] = clampFeedback((state.feedback[key] ?? 0) + delta.feedback[key]);
  for (const key in delta.floors) state.words[key] = Math.max(state.words[key] ?? 0, delta.floors[key]);
  for (const key in delta.sources) state.sources[key] = delta.sources[key];
  const known = new Set(state.seen);
  state.seen = [...state.seen, ...delta.seen.filter(id => !known.has(id))];
  bound(state);
  return state;
}

/** A copy of `base` with one session's delta applied; `base` is untouched. */
export function mergeDelta(base: Snapshot, delta: Delta): State {
  return applyDelta({ version: 1, words: Object.assign(counts(), base.words), bigrams: Object.assign(counts(), base.bigrams), trigrams: Object.assign(counts(), base.trigrams), feedback: Object.assign(counts(), base.feedback), sources: Object.assign(counts(), base.sources), seen: base.seen, rev: base.rev ?? 0 }, delta);
}

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

/** Set one `head\0word` count in a grouped index, so learning updates the index instead of rebuilding it. */
function setGroup(groups: Grouped, key: string, count: number): void {
  const cut = key.lastIndexOf('\u0000'), head = key.slice(0, cut);
  let words = groups.get(head);
  if (!words) groups.set(head, words = new Map());
  words.set(key.slice(cut + 1), count);
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

const SPACE = /\s/u;
/** The whitespace-delimited token around [start, end), or null beyond 160 characters (never prose). Linear in the token, not in the text. */
function tokenAround(text: string, start: number, end: number): string | null {
  let from = start, to = end;
  while (from > 0 && !SPACE.test(text[from - 1])) { if (end - --from > 160) return null; }
  while (to < text.length && !SPACE.test(text[to])) { if (++to - start > 160) return null; }
  return text.slice(from, to);
}

/** Web-frequency prior blended with typed unigram/bigram/trigram counts; no model or subprocess. */
export class GhostEngine {
  private lexicon: Lexicon;
  private state: State;
  private delta = emptyDelta();
  /** The shared-file revision this engine last wrote or adopted; a different one on disk means another session saved. */
  revision = 0;
  private typedOnly: string[] | undefined;
  private grouped: { bigrams: Grouped; trigrams: Grouped; feedback: Grouped } | undefined;
  constructor(lexicon: readonly string[], state?: Snapshot) {
    this.lexicon = parseLexicon(lexicon);
    this.state = { sources: {}, rev: 0, ...(state ?? { version: 1, words: {}, bigrams: {}, trigrams: {}, feedback: {}, seen: [] }) };
    this.revision = this.state.rev;
    for (const field of ['words', 'bigrams', 'trigrams', 'feedback', 'sources'] as const) Object.setPrototypeOf(this.state[field], null);
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
  /** Bytes of a history source already learned from. */
  seeded(source: string): number {
    return this.state.sources[source] ?? 0;
  }
  setSeeded(source: string, offset: number): void {
    this.state.sources[source] = offset;
    this.delta.sources[source] = offset;
  }
  /** Seed command names with their shell use counts as typed counts: log2 scaled, capped, idempotent. */
  learnCommandWords(uses: ReadonlyMap<string, number>): void {
    const { words, weights } = this.lexicon;
    for (const [raw, count] of uses) {
      const name = raw.toLowerCase();
      if (count < MIN_COMMAND_USES || !VOCABULARY_WORD.test(name)) continue;
      const at = lowerBound(words, name);
      if (words[at] === name && weights[at] >= COMMON_WEB_WEIGHT) continue;
      const seeded = Math.min(MAX_COMMAND_COUNT, 1 + Math.floor(Math.log2(count)));
      if (this.state.words[name] === undefined) this.typedOnly = undefined;
      if ((this.state.words[name] ?? 0) < seeded) this.state.words[name] = seeded;
      this.delta.floors[name] = Math.max(this.delta.floors[name] ?? 0, seeded);
    }
  }
  observe(text: string, id?: string): void {
    if (id && this.state.seen.includes(id)) return;
    if (id) { this.state.seen.push(id); this.delta.seen.push(id); if (this.state.seen.length > 4096) this.state.seen.shift(); }
    const masked = maskCode(text.slice(0, 20000));
    let previous = '', penultimate = '';
    for (const match of masked.matchAll(/[\p{L}\p{M}']+/gu)) {
      const word = match[0].toLowerCase();
      const token = tokenAround(masked, match.index!, match.index! + match[0].length);
      if (word.length > 64 || token === null || /[\\/@_=:{}\[\]<>\d]/u.test(token) || /\p{Ll}\p{Lu}/u.test(token)) { previous = ''; penultimate = ''; continue; }
      if (this.state.words[word] === undefined) this.typedOnly = undefined;
      bump(this.state.words, word); bump(this.delta.words, word);
      if (previous) { const k = previous + '\u0000' + word; bump(this.state.bigrams, k); bump(this.delta.bigrams, k); if (this.grouped) setGroup(this.grouped.bigrams, k, this.state.bigrams[k]); }
      if (penultimate) { const k = penultimate + '\u0000' + previous + '\u0000' + word; bump(this.state.trigrams, k); bump(this.delta.trigrams, k); if (this.grouped) setGroup(this.grouped.trigrams, k, this.state.trigrams[k]); }
      penultimate = previous; previous = word;
    }
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
      const score = (prior + (typed[word] ?? 0) + 4 * (afterPrev?.get(word) ?? 0) + 16 * (afterPair?.get(word) ?? 0)) * Math.exp(clampFeedback(bias?.get(word) ?? 0));
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
    const by = accepted ? FEEDBACK_ACCEPT : -FEEDBACK_REJECT;
    this.state.feedback[key] = clampFeedback((this.state.feedback[key] ?? 0) + by);
    bump(this.delta.feedback, key, by);
    if (this.grouped) setGroup(this.grouped.feedback, key, this.state.feedback[key]);
    if (accepted) this.observe(query.before + word);
  }
  snapshot(): Snapshot {
    if (bound(this.state)) { this.typedOnly = undefined; this.grouped = undefined; }
    return this.state;
  }
  /** Hand over what was learned since the last commit; later learning accumulates in a fresh delta. */
  takeDelta(): Delta {
    const taken = this.delta;
    this.delta = emptyDelta();
    return taken;
  }
  /** Put a delta back after a failed write. */
  restoreDelta(older: Delta): void {
    addDelta(this.delta, older);
  }
  /** Adopt the merged state other sessions saved (the caller hands the object over), keeping what was learned since it was taken. */
  rebase(owned: State): void {
    this.state = applyDelta(owned, this.delta);
    this.typedOnly = undefined; this.grouped = undefined;
  }
  /** A bounded copy of everything this session knows. */
  copyState(): State {
    return mergeDelta(this.state, emptyDelta());
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
