# Theme and transcript coloring evaluation

Legend: **[E]** executed/observed in this lab; **[C]** read in code/docs; **[H]** recommendation, inference, or untested behavior. All relative paths below are inside `/tmp/pi-lab/theme/`. Nothing was installed into the real Pi agent directory or changed in the Nix repository.

## Verdict and default

- **[E]** Required deliverable `omp-dark.json` is a strict Pi 1.3.0 truecolor port of OMP's stock dark palette, with explicit foregrounds, user/tool/custom backgrounds, diff/Markdown/syntax/thinking colors, and Pi's additional optional tokens. Real Pi loaded it through `--theme <absolute-file> --use-theme omp-dark`; the standard read/edit/bash/Markdown scenario made four fixture requests and `runs/omp-dark/raw.ansi` contains no theme-load errors or conflicts.
- **[E]** A JSON theme alone does **not** make Pi palette-independent: assistant prose, editor text, and unscoped highlight.js fragments still inherit the terminal foreground. This is why changing colors previously could leave the transcript yellow. `neutral-foreground.ts` fixes the observed prose/editor/native-code foreground without changing terminal colors or model messages. Its real-Pi proof is `runs/neutral/20-typing.png`.
- **[H]** For the user's literal screenshot target, ship **`omp-reference.json` as default**, **`omp-dark.json` as the stock-OMP/Dark+ alternate**, and the built-in **`system` as an optional palette-following alternate**. The screenshot-matched palette is visibly closer than stock dark: cyan keywords, green functions, yellow variables, gray comments. See `comparison-code.png`, then `runs/reference-native/20-typing.png` and `runs/reference-rich/20-typing.png` at full resolution.
- **[C/H]** `omp-reference.json` is a sampled-color reconstruction informed by the supplied `titanium` theme, not a claim that the user's exact OMP theme is known. Its sample-aligned syntax is intentionally different from the stock OMP `dark` palette. Keep both names distinct.
- **[H]** Use the neutral-foreground compatibility adapter only with the exact Pi 1.3.0 pin. Prefer an upstream default Markdown/editor foreground hook when available. Rich TextMate highlighting is demonstrated without a fork, but the public-API prototype has UI tradeoffs; keep it opt-in rather than silently replacing all native edit rendering.

## Visual candidates, all exercised in real Pi

**[E]** `comparison-themes.png` is the six-way standard-scenario contact sheet. Each run also contains startup, typed prompt, completed turn, typing, expanded tools, narrow-width screenshots, raw ANSI, fixture requests, and result JSON.

| Candidate | Screenshot | Observation / recommendation |
|---|---|---|
| `system` | `runs/system/10-after-turn.png` | **[E]** Mona-Lisa yellow body text, low-contrast ANSI keywords, no visible card fills in this lab. **[C]** Its documented live-terminal mode derives contrast-adjusted colors from OSC replies; the observed lab output remained ANSI fallback, so this is not proof that its adaptive live-terminal mode is poor. |
| `terminal` | `runs/terminal/10-after-turn.png` | **[E]** Direct ANSI mapping preserves the user's muted warm palette, lacks distinct card backgrounds, and does not resemble OMP. **[H]** Do not use as default. |
| `terminal-tinted`, unmodified xterm slots | `runs/terminal-tinted/10-after-turn.png` | **[E]** Harsh saturated blue tool fills from standard xterm slots. **[C]** Slots 16–23 are not dim ANSI colors. Disqualified as a default without explicit terminal remapping. |
| `terminal-tinted`, remapped | `runs/terminal-tinted-remapped/10-after-turn.png` | **[E]** Card fills become restrained, but syntax/prose still follow Mona Lisa. **[H]** No advantage over the self-contained truecolor theme for this user. |
| Existing `managed-opencode` | `runs/managed-opencode/10-after-turn.png` | **[E]** Muted purple/green palette and blue-green cards, still terminal-yellow prose/unscoped code. **[H]** It does not match the supplied OMP code crop as closely as the sampled reconstruction. |
| New stock `omp-dark` | `runs/omp-dark/10-after-turn.png` | **[E]** Correct Dark+-style syntax tokens and restrained OMP user/tool cards, but terminal-yellow unscoped content persists without the adapter. |
| `omp-dark` + neutral adapter | `runs/neutral/20-typing.png` | **[E]** Neutral body/editor and unscoped native code; no model-message modification or terminal palette mutation. |
| Sampled `omp-reference` + neutral | `runs/reference-native/20-typing.png` | **[E/H]** Best conservative default for the screenshot goal; native function-call detection remains visibly less rich than OMP. |
| Sampled palette + neutral + TextMate | `runs/reference-rich/20-typing.png` | **[E]** Closest code-color result: function calls such as `Println` and `add` have distinct function colors, punctuation and variables no longer depend on terminal yellow. |

- **[E]** OMP reference crops are copied locally as `crop_omp_code.png` and `crop_omp_status.png`; `comparison-code.png` compares the reference with stock-dark native, sampled native, and sampled TextMate code.
- **[E]** `runs/card-states/10-pending.png` and `20-success-error.png` show the actual user, pending, successful, and failed tool cards under `omp-dark` plus the neutral adapter. All fills are explicit RGB; a missing-file error was intentional fixture behavior.
- **[E]** `lab-palette.py` is an isolated driver copy adding `palette_slots` rendering/OSC replies. The remapped run uses selected/error/success/pending/user/custom/title/output slots from `scenario-terminal-tinted-remapped.json`; the terminal's 0–15 palette remains Mona Lisa.
- **[E]** The baseline and a startup-synchronized diagnostic run both emitted 18 OSC color queries but only four foreground truecolor sequences under `system`. Delaying child launch until font loading completed did not change the fallback appearance; see `runs/system-synchronized/10-after-turn.png`. **[H]** The remaining OSC-negotiation limitation belongs to the lab/terminal interaction, not an established Pi defect.

## What Pi 1.3.0 actually uses

- **[C]** Pi depends on **highlight.js 10.7.3**, not syntect and no longer cli-highlight. `dist/utils/syntax-highlight.js` calls highlight.js, converts its HTML scope spans into ANSI with Pi's own scope-stack renderer, and decodes entities. A few comments in `theme.js` still mention cli-highlight, but it is not the imported renderer.
- **[C]** Twenty-one grammars are eager: Python, Java, Go, JavaScript, JSON, C++, TypeScript, PHP, Ruby, C, C#, Nix, Bash, Rust, Scala, Kotlin, Swift, Dart, Groovy, Perl, Lua. `loadAllHighlightLanguages()` imports the full installed library asynchronously during interactive startup.
- **[C]** The installed full library registers **191 grammar names**, recorded in `highlight-languages.json`. Its `literalAliases` field records first literal source declarations, not evaluated runtime aliases; do not use that auxiliary field as an exact alias inventory.
- **[C]** Explicit fence languages are used only when supported. Missing/unknown languages fall back to `mdCodeBlock`; Pi deliberately avoids automatic language detection for prose safety. There is no user highlight-options setting that switches engines or makes unclassified tokens semantic.

### Scope-to-theme mapping

**[C]** Source: Pi `dist/modes/interactive/theme/theme.js:711–739`.

| highlight.js scopes | Pi token |
|---|---|
| `keyword`, `name` | `syntaxKeyword` |
| `built_in`, `class`, `type` | `syntaxType` |
| `literal`, `number` | `syntaxNumber` |
| `regexp`, `string` | `syntaxString` |
| `subst` | `text` |
| `comment`, `doctag` | `syntaxComment` |
| `meta` | `muted` |
| `function`, `title` | `syntaxFunction` |
| `attr`, `variable`, `params` | `syntaxVariable` |
| `operator` | `syntaxOperator` |
| `tag`, `punctuation` | `syntaxPunctuation` |
| `addition`, `deletion` | `toolDiffAdded`, `toolDiffRemoved` |
| `emphasis`, `strong`, `link` | italic, bold, underline |
| unclassified text | no formatter / terminal foreground |

**[C]** Exact scope wins, then dotted/dashed prefixes, then the innermost matching ancestor. There is no default formatter in this theme mapping. This explains the large terminal-yellow fraction, even when a language does receive syntax colors.

### Requested language proof

**[E]** `syntax-probe.ts` runs the actual public `highlightCode`, `getMarkdownTheme().highlightCode`, and `getLanguageFromPath` inside real Pi. `syntax-native.json` contains the ANSI results. Markdown and tool highlighter output matched for every probe. Counts below are distinct explicit RGB foregrounds in these particular samples, not grammar coverage guarantees.

| Language | Explicit RGB colors | File-path mapping | Finding |
|---|---:|---|---|
| Go | 6 | `.go` → Go | **[E]** Distinct keywords, declared function names, params, strings, numbers, comments; ordinary calls/identifiers often plain. |
| Nix | 5 | `.nix` → **undefined** | **[E/C]** Nix fences work because Nix grammar is eager; read/write cards miss it because `.nix` is absent from `getLanguageFromPath`. |
| TypeScript | 7 | `.ts` → TypeScript | **[E]** Distinct colors, but not compiler semantic tokenization. |
| Python | 8 | `.py` → Python | **[E]** Distinct colors. |
| Rust | 6 | `.rs` → Rust | **[E]** Distinct colors. |
| Bash | 6 | `.sh` → Bash | **[E]** Distinct colors. |
| JSON | 3 | `.json` → JSON | **[E]** Keys/strings, numbers/booleans, and plain punctuation are distinguishable. |
| Markdown | 1 | `.md` → Markdown | **[E/C]** This sample receives mostly bold/italic/underline, not a rich color palette: scope classes such as section/bullet/code are not in Pi's mapping. |
| Diff | 3 | `.diff` → **undefined** | **[E]** Explicit diff fences color additions/removals/metadata; path detection does not identify `.diff`. |

### Tool cards

- **[C]** `read` normally shows its content only when expanded, determines language from file extension, then uses the same `highlightCode`. Unknown extensions use `toolOutput`. Native read rendering preserves image handling and truncation notices. See `dist/core/tools/renderers/read.js:82–123`.
- **[C]** `write` highlights content using the same path mapping and incremental cache, with a shortened preview unless expanded; it is not a different highlighter.
- **[C]** Native `edit` does **not** syntax-highlight the source inside diff lines. `components/diff.js:70–131` uses green/red/gray for whole lines and inverse word changes only for one-removed/one-added-line replacements. Its `filePath` option is currently unused. Edit preview rendering happens asynchronously in the call card before tool completion.
- **[E]** Nix before/after read + edit + fence screenshots: `runs/nix-cards-native/10-read-edit-code.png` versus `runs/nix-cards-rich/10-read-edit-code.png`. These directly demonstrate both missing `.nix` path mapping and richer syntax inside diff lines.

## OMP comparison and the no-fork route

- **[C]** OMP's native highlighter uses **syntect** with a bundled syntax set, maps scopes to **11 categories** (the nine syntax categories plus inserted/deleted), caches scope classifications, and has many explicit alias groups including TypeScript/TSX, Nix, shell, Go/golang and other languages. Source: [OMP highlight.rs](https://raw.githubusercontent.com/can1357/oh-my-pi/main/crates/pi-natives/src/highlight.rs).
- **[C]** Both engines are grammar/scope highlighters, not LSP compiler-semantic highlighting. The visible difference is grammar scope quality, alias/path coverage, default/unscoped behavior, and color mapping—not merely the number of JSON syntax tokens. Pi already has nine syntax tokens plus diff-added/deleted colors.
- **[C]** Pi's public API offers `registerMarkdownTransformer(markdown, context)` and `registerToolRenderer((toolName, next) => ...)`, but no setter for the core MarkdownTheme highlighter/default body style. A transformer changes rendered Markdown only, not model context.
- **[E]** `rich-highlighting.ts` is a working no-fork public-API proof: bundled **Shiki 4.5.0** TextMate grammars + local inlined Oniguruma WASM; a custom theme maps scopes to Pi's existing 11 categories. It handles Go/Nix/TS/TSX/JS/Python/Rust/Bash/JSON/Markdown/diff and common short aliases, replaces expanded read rendering, and highlights old/new diff sides separately to retain multiline state within each side.
- **[E]** The prototype uses an explicit `[TextMate]` suffix on recognized code fences to bypass Pi's second highlighter. Completed code blocks receive rich color; streaming text remains native until the fence closes. This is a deliberate visible prototype marker, not a claim of a hidden highlighter hook.
- **[E]** The standard rich run and both language/Nix runs completed real tool calls; before/after screenshot families are `runs/rich*`, `runs/languages-*`, and `runs/nix-cards-*`. No extension-load/runtime exceptions were found in the exercised raw ANSI.
- **[H]** Do not ship this exact renderer as an invisible drop-in: it replaces native edit preview behavior and loses native inverse word-change emphasis; read metadata-only truncation warnings need parity review; unsupported languages fall back to native; nested/unclosed Markdown fences stay native; the custom theme expects truecolor theme tokens and does not prove live `/settings` theme-switch parity. These are bounded prototype limitations, not deferred claims of completion.
- **[H]** Recommended production direction: neutral default foreground plus native highlighter first; optional richer renderer when those UI tradeoffs are acceptable, or request upstream public hooks for default Markdown style / `highlightCode`. Merely setting more JSON syntax colors cannot recover function-call scopes that highlight.js never emits or add `.nix` path detection.

## Neutral foreground compatibility adapter

- **[E]** `neutral-foreground.ts` wraps the exported `Markdown.prototype.render` and `CustomEditor.prototype.render`, explicitly colors default foreground spans using the selected theme's `text`, and reopens that color after SGR foreground resets. Existing syntax/Markdown/border/selection colors are preserved in the exercised scenarios. It does not issue OSC palette mutations, spawn processes, access the network, write files, or alter model/session content.
- **[C/H]** This is an exported-component method adapter, **not a documented extension hook**. It must be reviewed on Pi upgrades and when combined with editors that fully replace rendering rather than inherit from CustomEditor. It restores the previous methods on shutdown and reads the current UI theme at render time; live theme switching and all third-party editor combinations were not exercised.

## npm pin and safety inventory

**[C]** Complete required top-level metadata (exact version, integrity, non-peer dependencies, lifecycle scripts, native modules, bin, license, unpacked size, behavior) is in `npm-audit.json`. Every installed transitive version/integrity, dependency list, lifecycle script, bin and license is in `dependency-audit.json` and `package-lock.json`.

| Candidate | Pin / footprint | Safety result |
|---|---|---|
| `pi-terminal-theme` | **[C]** `0.2.0`; 7,877 bytes unpacked; MIT; no deps, bin, install/postinstall/prepare scripts, or native modules. Exact integrity in `npm-audit.json:89`. | **[C]** Five-file JSON/docs/license package, no executable runtime code, network, child processes or fs writes. Pure immutable theme resource; not needed for the recommended default. |
| `shiki` | **[C/E]** `4.5.0`; 602,495 bytes for the root tarball; MIT; no bin or install/postinstall/prepare scripts. Eight direct non-peer dependencies are enumerated in `npm-audit.json:5–14`; lock pins 45 installed dependencies, about 15 MB total files. Exact root integrity in `npm-audit.json:4`. | **[C/E]** No `.node` addons or `binding.gyp` found in the installed tree. TextMate JS + bundled/inlined Oniguruma WASM; no runtime binary/grammar/model download in the exercised/default import path. |

- **[C]** Audited Shiki/core/engine runtime source contains no network `fetch`, child-process, fs-read/fs-write, or telemetry calls. The generic Oniguruma loader can consume a caller-provided `Response`; the selected default path imports `@shikijs/engine-oniguruma/wasm-inlined` locally instead. Grammar text containing words such as `fetch` is not executable network code.
- **[E]** Install used `npm install --ignore-scripts --no-audit --no-fund` with HOME/cache inside the theme lab. One transitive package, `regex-utilities`, declares `prepare: npm test`; it was not executed. No runtime installation path is present in either prototype.
- **[H]** If the richer renderer is selected, use the included fixed lock in an immutable Nix build, disable lifecycle scripts, and preserve the bundled WASM/grammar assets. Do not use `pi install` or runtime dependency resolution/downloads.
- **[C]** Registry sources: [pi-terminal-theme 0.2.0](https://registry.npmjs.org/pi-terminal-theme/0.2.0), [Shiki 4.5.0](https://registry.npmjs.org/shiki/4.5.0). Pi format reference: [strict theme schema](https://pi.dev/schemas/theme.schema.json).

## Evidence boundaries

- **[E]** Every run used the pinned real Pi 1.3.0 binary, a PTY, the supplied font/palette emulator, local project files, and a localhost scripted fixture provider. No real LLM endpoints or credentials were used. All screenshots/prototypes referred to here are under this directory.
- **[E]** Exercised: all requested standard theme candidates, both tinted-slot modes, custom-theme validation, pending/success/error cards, native highlighter probes, eight-language transcripts, Nix read/edit before/after, foreground compatibility adapter, TextMate extension, expanded tools, typing, and narrow resize.
- **[H]** Not established: perfect OMP layout parity (belongs to visuals), exact original OMP theme identity, successful live system-theme OSC adaptation in the user's Ghostty session, all grammar aliases, compile-semantic tokens, all streaming Markdown edge cases, accessibility contrast for every alternate, or combined compatibility with the other evaluators' final extensions.
