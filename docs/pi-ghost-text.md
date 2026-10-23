# Local Pi ghost-text word completion

`local.pi.ghostText.enable` is on by default with `local.pi.enable`. The extension completes the **current prose word**, not a sentence or an earlier prompt. It never calls a provider, starts a subprocess, downloads a dictionary/model, or sends telemetry. Native command/path autocomplete has precedence.

```nix
local.pi.ghostText = {
  enable = true;
  # Optional immutable plain UTF-8 list, one word per line:
  # wordList = ./my-words;
};
```

The default is the single `wamerican.35` file copied from locked nixpkgs `scowl`; its SHA-256 is asserted during the build: `b31d847c962c964791909717a0b85ed977a6cd12b468687564291efc5b796e7a`. No npm plugin or additional runtime dependency is used. `local.pi.ghostText.entries.ghostText` exposes the generated immutable entry. It is ordered after normal UI entries; `resources_discover` decorates whichever editor the visual owner installed during `session_start`.

Encoding correction to the evaluation prototype: the pinned SCOWL file is **ISO-8859-1, not UTF-8**. Loading first tries strict UTF-8, then Latin-1 for SCOWL; accented words are preserved rather than silently replaced. Custom UTF-8 lists remain supported.

## Keys and gates

- **Tab:** accept the suffix and a normal trailing space.
- **Right:** accept without a space.
- **Escape:** dismiss this suggestion until the input changes.
- Divergent typing rejects the suggestion; typing through its matching prefix does not penalize it.
- No suggestion while unfocused, native autocomplete is open, the cursor is not at logical end-of-line, the prefix has fewer than two characters, or confidence is below 0.15.
- Omit commands (`/`), queue shorthand (`->`, `=>`), code fences/spans, HTML tags/blocks/comments, digit-bearing tokens, camelCase, paths and tokens containing `\\ / @ _ = : { } [ ] < >`. Maximum buffer/line sizes are 20,000/1,000 UTF-16 units.

## Learning and private state

The engine interpolates dictionary/unigram, bigram and trigram scores, preserves uppercase suffixes, and learns user/assistant prose from the active transcript and subsequent `message_end` events. Tool output is excluded. Stable message hashes deduplicate replay; accept/reject feedback changes candidate ranking.

`<agent-dir>/ghost-text-state.json` is a separate writable overlay, never a managed settings file. Writes are debounced (500 ms), serialized, atomic temp/rename, mode **0600**, and flushed on shutdown. Stored data is counts/n-grams/feedback and message hashes, not complete prompts; **vocabulary and phrases can still be sensitive**. Bounds at snapshot time: 30,000 words, 40,000 bigrams, 40,000 trigrams, 10,000 feedback pairs and 4,096 message IDs. Missing dictionaries disable completion with one visible warning. Invalid/corrupt state is ignored with one warning. Write failures warn once without breaking the editor.

Independent processes sharing one agent directory do **not** merge/lock learning: last writer wins. A read-only parent directory prevents persistence but not completion; the managed `settings.json` symlink is never changed. Project settings cannot override the entry's word-list option. Non-TUI modes (`-p`, JSON, RPC) and `PI_SUBAGENT_CHILD=1` are no-ops without dictionary reads, UI notices, or state writes.

## Honest parity with omp

Reference: [omp predictor source at `0b5c27a`](https://github.com/can1357/oh-my-pi/tree/0b5c27ab24719c86a5986b95ee55f4e75bc1aaa0/crates/pi-predict). This is a small local implementation, **not a port of its full statistical engine**.

| Area | This extension versus omp |
|---|---|
| Inline word suffix, Tab/Right, prose gates, 0.15 threshold | Matched in purpose; conservative masking and two-character minimum are stricter. |
| Local dictionary and transcript n-grams | Present; simple weighted counts, not omp's absolute-discount/interpolated probabilities. |
| Candidate confidence | Normalized prefix mass; unlike omp a finished word winning the ranking suppresses an extension entirely. |
| Web-frequency prior, learned case channel, spelling canonicalization | Not implemented; cold ranking is weaker/uniform. |
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

The check covers unit behavior/persistence and real Pi with an independent visual owner in **both load orders**, actual buffer versus painted suffix, Tab/Right/Escape, gates/native popup, 40 columns/CJK/emoji, two reloads and `/new`, zero completion-provider requests, and quiet print/JSON smoke requests to a scripted localhost provider. Verification with the full pi-omp-theme combination is reserved for the coordinator's integration check, not claimed by this slice check.
