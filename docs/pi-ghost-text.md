# Local Pi ghost-text word completion

`local.pi.ghostText.enable` is on by default with `local.pi.enable`. The extension completes the **current prose word**, not a sentence or an earlier prompt. It never calls a provider, starts a subprocess, downloads a dictionary/model, or sends telemetry. Native command/path autocomplete has precedence.

```nix
local.pi.ghostText = {
  enable = true;
  # Optional immutable vocabulary, one word per line with an optional TAB-separated web frequency:
  # wordList = ./my-words;
};
```

The default is a generated vocabulary of about 332,000 words (`ghost-vocabulary.tsv`) built from locked nixpkgs; see [Vocabulary and ranking](#vocabulary-and-ranking). No npm plugin or additional runtime dependency is used. `local.pi.ghostText.entries.ghostText` exposes the generated immutable entry. It is ordered after normal UI entries; `resources_discover` decorates whichever editor the visual owner installed during `session_start`.

Loading first tries strict UTF-8, then Latin-1, so a custom SCOWL-derived list keeps accented words rather than silently replacing them.

## Keys and gates

- **Tab:** accept the suffix and a normal trailing space.
- **Right:** accept without a space.
- **Escape:** dismiss this suggestion until the input changes.
- Divergent typing rejects the suggestion; typing through its matching prefix does not penalize it.
- No suggestion while unfocused, native autocomplete is open, the cursor is not at logical end-of-line, the prefix has fewer than two characters, or confidence is below 0.3.
- Omit commands (`/`), queue shorthand (`->`, `=>`), code fences/spans, HTML tags/blocks/comments, digit-bearing tokens, camelCase, paths and tokens containing `\\ / @ _ = : { } [ ] < >`. Maximum buffer/line sizes are 20,000/1,000 UTF-16 units.

## Vocabulary and ranking

Each vocabulary line is `word<TAB>weight`; the weight is the word's share of web text, absent for words that only a dictionary or a package name supplies. `packages/pi-ghost-wordlist.nix` generates the default from locked nixpkgs:

- **Web frequency prior:** the `large` English list of `wordfreq` 3.2.0 (about 311,000 words). Its data is CC BY-SA 4.0 (see its `NOTICE.md`); the build only produces a local, undistributed list.
- **Dictionary words:** SCOWL `wamerican.35` adds words the frequency list lacks. Its SHA-256 is asserted during the build: `b31d847c962c964791909717a0b85ed977a6cd12b468687564291efc5b796e7a`.
- **Tool names:** the tokens of nixpkgs package names (`kubectl`, `terraform`, `ripgrep`) that no English list carries. Each package name using a token adds `2e-9`, a popularity proxy: `kubectl`, with dozens of plugin packages, outranks `kubecolor` for `kubec`, and every tool token stays far below any real web frequency.

Under a typed prefix every vocabulary word, **the finished prefix included**, shares one probability mass. A word scores `1000 × web weight + times you typed it + 4 × times typed after the previous word + 16 × times typed after the previous two words`, scaled by accept/reject feedback. The best *extension* is shown when it holds at least **0.3** of that mass, so `th` completes to `the`, `hel` to `help` and `kubec` to `kubectl`, while a broad prefix such as `under` stays silent and a finished, very common word such as `the` is not extended. A word outside the vocabulary (a project or product name) is suggested only after you typed it twice.

The prior strength (1000) and the 0.3 gate were tuned on the maintainer's own typed prompts, replaying every keystroke inside a word. Correct suggestions per 100 such keystrokes: 33 without learned history and 58 with it, against 12 and 49 for the earlier uniform dictionary prior at a 0.15 gate, and 18 and 55 when that gate was lowered to 0.04. Lowering the gate alone also made the suggestion wrong about half the time.

## Learning and private state

The engine preserves uppercase suffixes and learns user/assistant prose from the active transcript and subsequent `message_end` events. Tool output is excluded. Stable message hashes deduplicate replay. Accept/reject feedback only nudges the ranking: an acceptance can lift a word up to e³, a rejection lowers it by e^0.25 per event down to e^-1 of its mass, so typing past a suggestion (usually a different word, not a wrong ranking) can never hide the dominant word of a prefix. The earlier ±6 bounds did exactly that for prefixes like `th`, and persisted values beyond the new bounds are clamped when read.

`<agent-dir>/ghost-text-state.json` is a separate writable overlay, never a managed settings file. Writes are debounced (500 ms), serialized, atomic temp/rename, mode **0600**, and flushed on shutdown. Stored data is counts/n-grams/feedback and message hashes, not complete prompts; **vocabulary and phrases can still be sensitive**. Bounds at snapshot time: 30,000 words, 40,000 bigrams, 40,000 trigrams, 10,000 feedback pairs and 4,096 message IDs. Missing dictionaries disable completion with one visible warning. Invalid/corrupt state is ignored with one warning. Write failures warn once without breaking the editor.

Independent processes sharing one agent directory do **not** merge/lock learning: last writer wins. A read-only parent directory prevents persistence but not completion; the extension never changes the managed `settings.json`. Project settings cannot override the entry's word-list option. Non-TUI modes (`-p`, JSON, RPC) and `PI_SUBAGENT_CHILD=1` are no-ops without dictionary reads, UI notices, or state writes.

## Honest parity with omp

Reference: [omp predictor source at `0b5c27a`](https://github.com/can1357/oh-my-pi/tree/0b5c27ab24719c86a5986b95ee55f4e75bc1aaa0/crates/pi-predict). This is a small local implementation, **not a port of its full statistical engine**.

| Area | This extension versus omp |
|---|---|
| Inline word suffix, Tab/Right, prose gates | Matched in purpose; conservative masking and two-character minimum are stricter. The show threshold is 0.3 here, omp's is 0.15, because the two engines' confidences are not comparable. |
| Local vocabulary and transcript n-grams | Present; simple weighted counts, not omp's absolute-discount/interpolated probabilities. |
| Candidate confidence | Normalized mass over all words under the prefix, the finished prefix included; the best extension is returned, as in omp. |
| Web-frequency prior | Present with different data: `wordfreq` (about 311,000 words) instead of omp's Norvig 2006 top 150,000, and no web bigrams. Tool names come from nixpkgs package names. |
| Words outside the vocabulary | Suggested after two typings, as omp's unknown-word minimum. |
| Learned case channel, spelling canonicalization | Not implemented. |
| SmolLM2-135M, Apple spelling engine, neural blending/cache/daemon | Not implemented; no model weights or runtime downloads. |
| Feedback learning | Implemented here; omp currently sends feedback but its predictor implementations leave it a no-op. |
| Punctuation-absorbing provisional Tab space | Not matched: Tab adds an ordinary space. |
| Async projection/single-flight queue | Unneeded for this synchronous in-process engine; not copied. |

## Editor compatibility and verification

The wrapper returns the **same editor instance** and restores its methods/factory on shutdown. It needs `focused`, `getCursor`, `getLines`, `insertTextAtCursor`, standard `render`/`handleInput`; `isShowingAutocomplete` is optional but needed to detect a custom editor's native popup. Unsupported editors receive one warning and are left unchanged. Pi 1.3.0 cursor/fake-cursor APC markers are a version-coupled rendering dependency: only trailing padding is replaced, preserving borders and line widths. A visual owner replacing its factory *after* resource discovery can displace completion until the next discovery/reload.

```sh
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix build --no-link .#checks.x86_64-linux.pi-ghost
```

The check covers unit behavior/persistence, the generated default vocabulary (`kubectl`, `th`, `the`), and real Pi with an independent visual owner in **both load orders**, actual buffer versus painted suffix, Tab/Right/Escape, gates/native popup, a tool name from the package-name prior, 40 columns/CJK/emoji, two reloads and `/new`, zero completion-provider requests, and quiet print/JSON smoke requests to a scripted localhost provider. `pi-omp-parity` exercises the same completion inside the combined omp UI, LSP and role configuration.
