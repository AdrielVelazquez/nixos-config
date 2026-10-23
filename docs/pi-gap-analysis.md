# Pi vs omp vs OpenCode: gap analysis

Date 2026-10-23. Versions: Pi 1.3.0 (`pkgs.pi-coding-agent`), omp 18.12.6 (flake pin `v18.12.6`), OpenCode 2.0.26 (docs
read from opencode.ai/docs, which also describe v1 behavior). Evidence labels: **[E]** executed here, **[C]** read in
docs/source, **[H]** inference. Screenshots and per-area reports: `docs/reviews/2026-10-23-pi-omp-parity-evaluation/`.
"This branch" shows what `feat/pi-omp-parity` closes: **closed**, **partial**, **open** (not attempted), **n/a**.

## 1. Why Pi looked worse (measured, not guessed)

| Observation | Cause | Evidence |
|---|---|---|
| Whole transcript yellow and muddy | Pi paints assistant prose, editor text and unclassified code tokens in the terminal's *default foreground* (`#f7d66a` in Ghostty "Mona Lisa"); no theme token reaches it. omp paints its own text color. | [E] theme report; `images/baseline-default-pi.png` |
| Thin `\|` editor, 3-line uppercase footer | `pi-zentui` + local `visuals.ts` choices, not Pi defaults | [E] `visuals-report.md` |
| Pastel hex palette | `managed-opencode` theme replaced Pi's terminal-aware `system` theme | [C] `dotfiles/pi/themes/managed-opencode.json` |
| Code blocks nearly monochrome | highlight.js scopes map to 9 theme tokens; calls/identifiers are unclassified and inherit the terminal foreground; edit diffs are not syntax-highlighted | [C]/[E] theme report |
| No LSP | Pi has none; main only had the Serena MCP; `pi-lsp-extension` was audited out | [C] `docs/pi.md` |

## 2. Capability matrix

| Area | Pi 1.3.0 default | omp 18.12.6 | OpenCode 2.0.x | This branch |
|---|---|---|---|---|
| Status line | one native footer row (cwd, model, context) | presets `default/minimal/compact/full/nerd/ascii/custom`, separators, segments (model, path, git, cost, context, ...), session accent on the editor border [C] | footer line with path:branch, context and cost [E: screenshot] | **closed**: `pi-omp-theme` preset `omp`, one powerline row |
| Tool cards | native boxes tinted by theme | compact reads, framed edit/bash cards, highlighted diffs with counts [C] | inline cards, `diff_style auto/stacked` [C] | **closed** via `pi-omp-theme` (guarded private adapters) |
| Themes | `system` (OSC-adaptive), dark, light, custom JSON | 100 bundled themes, symbol presets (nerd/unicode/ascii) [E: 100 files] | JSON themes, system theme [C] | **closed**: `omp-reference` (default), `omp-dark`, optional `pi-terminal-theme` |
| Prompt box | bordered editor | rounded composer with status on its border [C] | left-bar panel, model line [E: screenshot] | **closed** (omp style); OpenCode-style panel **open** |
| Inline word completion | none | ghost text: n-gram / SmolLM / macOS spelling [C] | none documented | **closed** (own dictionary n-gram; no web prior or SmolLM) |
| `@` file mentions, `/` commands, `!` shell | yes | yes | yes | n/a (native) |
| Vim keys in editor | no | optional vim mode [C `keybindings.md`] | no | **open** |
| LSP diagnostics after writes | none | every write; push/pull freshness; optional format-on-write [C] | diagnostics feedback, opt-in `lsp:true`, ~35 servers [C] | **closed** (patched `pi-lsp`, nixpkgs servers); format-on-write and omp's deferred late delivery **open** |
| LSP navigation tools | none | `lsp` tool, 14 actions incl. rename, rename_file, code actions, raw request [C] | experimental `lsp` tool [C] | **closed**: definition, references, hover, symbols, rename preview, code actions; rename_file/raw request **open** |
| Formatters | none | via LSP/Biome writethrough [C] | ~25 built-in, opt-in [C] | **open** |
| Structural search/edit | extension `pi-ast-grep` (read-only here) | `ast_grep`, `ast_edit` native [C] | none documented | n/a (kept) |
| Edit format | `oldText/newText` | hashline content-hash anchors, plus apply_patch/patch/replace modes [C] | edit + apply_patch [C] | **open** |
| Execution | bash, optional `codemode` QuickJS | persistent Python+JS eval with tool re-entry, in-process shell [C] | shell [C] | **open** |
| Debugger | none | DAP, 28 ops [C] | none | **open** |
| Subagents | none built in; `pi-subagents` package | `task` with worktree isolation, Agent Hub, typed `yield` [C] | primary + subagents, `@` mention [C] | n/a (kept `pi-subagents`) |
| Model routing | `/model`, scoped models + Ctrl+P, **virtual models** API | 10 chat roles + kinds, `/models` screen, fallback chains, cycleOrder, `--smol/--slow/--plan`, role aliases [C/E screenshot] | per-agent model, variants, hidden compaction/title/summary agents [C] | **closed** for consumable roles via `roles/auto`; see 4 |
| Advisor / judge / auto-thinking | none | advisor watchdog, `judge` role [C] | none | **partial**: `/advisor` command only |
| Memory | Headroom MCP (repo) | retain/recall/reflect backends [C] | rules files [C] | n/a (kept Headroom) |
| Stream rules | none | TTSR [C] | none | **open** |
| Review / commit | none | `/review` P0-P3 verdict, `omp commit` atomic splits [C] | GitHub/GitLab Actions integrations [C] | **partial**: `/commit` drafts a message |
| Web / browser / desktop | extension `pi-web-access` (fetch plus Exa-only `web_search` here) | 23-provider `web_search`, browser, computer use [C] | webfetch, websearch [C] | n/a (kept) |
| Sessions / share / collab | tree, fork, clone, export, share | export/share, `/collab`, ACP, RPC, handoff [C] | web UI + attach, server, IDE, ACP, `/export` [C] | n/a |
| Extensibility | extensions (jiti), packages (npm/git), skills, templates | marketplace/plugins, hooks, custom tools [C] | plugins, custom tools/commands/skills [C] | n/a |
| Permissions | project trust; extension-level | approval tiers per tool [C] | allow/ask/deny with granular rules, auto mode [C] | n/a (read-only profile kept) |
| Usage dashboard | `/session` stats | `omp stats` [C] | none read | **closed** by `pi-stats` (see 3) |

## 3. Answers to the user's four observations

1. **LSP "not working as expected".** Correct: Pi has no LSP and the repo had excluded the candidates. Now: diagnostics after every
   `edit`/`write` land in the tool result the model reads next, navigation tools exist, `LSP gopls ● · typescript ●` shows in the
   footer, and servers include every language the user's Neovim configures. A stock plugin would not have worked: with real gopls the
   leading plugin silently skipped post-edit diagnostics (it gated on a pull-diagnostics capability gopls does not advertise), and two
   others attached stale errors after a repair [E]. Two small named patches are carried: the 15-line eligibility fix and a silence fix
   found by the combined check (a clean TypeScript edit waited the whole 15 s window, then reported a timeout; it now reads as clean
   after at most 3 s). See `docs/pi-lsp.md`.
2. **omp's word autocomplete.** It is inline ghost text from omp's `pi-predict` crate (n-gram over a compressed web prior; opt-in
   SmolLM-135M; macOS spelling), shown only at the end of a prose word, accepted with Tab (Right Arrow without the space). Upstream
   feedback learning is currently a no-op in all three engines [C]; the Pi extension implements real accept/reject learning over a
   nixpkgs-built web-frequency vocabulary (wordfreq, SCOWL, package names) plus the user's own transcript, offline. Not matched: web
   bigrams, SmolLM, punctuation-absorbing space. See `docs/pi-ghost-text.md`.
3. **omp's package table.** What each `@oh-my-pi/*` package means for plain Pi:

   | Package | Usable with plain Pi? | Decision |
   |---|---|---|
   | `omp-stats` | **Yes [E]**: `omp stats --summary --json` ingested real Pi session JSONL (format v3) and reported requests, tokens, cache rate and cost; it writes only `~/.omp/stats.db` and its native-library cache | shipped as `pi-stats` (reads `~/.pi/agent/sessions`, private HOME) |
   | `pi-mnemopi` | MCP server (`mnemopi mcp`) could back Pi's MCP | not adopted: Headroom memory already owns memory |
   | `pi-natives` | N-API addon (grep, shell, syntect highlight, image, text) | not adopted: per-platform native build; syntect would improve code coloring later |
   | `snapcompact` | library for bitmap context compaction (vision models) | not adopted |
   | `pi-tui`, `pi-ai`, `pi-agent-core`, `pi-catalog`, `pi-utils`, `pi-wire` | omp's forks of Pi's own libraries | n/a: Pi supplies its own copies to extensions |
   | `omptype`, `metaharness`, `typescript-edit-benchmark`, `browser-relay`, `collab-web` | benchmarks/validation/omp-specific features | n/a |

4. **Model routing.** Implemented as a native virtual model (`roles/auto`) plus a `/models` role screen, flags and a writable overlay
   (see `docs/pi-model-roles.md`). Not reproduced: advisor watchdog, memory engine, judge/auto-thinking, path-scoped `enabledModels`,
   round-robin credentials, usage-aware fallback, Retry-After parsing. Pi's native `/model` still selects a physical model and
   intentionally bypasses the router.

## 4. What is still open (ranked by likely value)

1. Format-on-write (OpenCode formatters / omp writethrough): needs a formatter set from nixpkgs and a post-write hook.
2. Hashline edit mode: fewer retries on weak models; needs a custom edit tool, a large behavior change.
3. Syntect-grade code coloring: the evaluated Shiki prototype (`docs/reviews/.../theme-report.md`) works but replaces native
   read/edit rendering; the user chose to skip it for now.
4. OpenCode-style prompt panel (left bar + fill) and per-answer footers.
5. DAP, TTSR, Agent Hub-style subagent supervision, `/review` verdicts: each is a standalone extension project.

## 5. Residual risks of this branch

- `pi-omp-theme` decorates Pi internals through guarded prototype adapters; `neutral-foreground` wraps `Markdown`/`CustomEditor`
  render methods. Both are pinned to Pi 1.3.0 behavior and fall back to native rendering when a contract changes.
- `settings.json` is a writable copy that every Home Manager switch overwrites from Nix: runtime choices (`/lsp` global scope,
  `/subagents-watchdog`, `/pi-omp-theme persist`) last only until the next switch, and a rollback to an older generation needs the file deleted first.
- Overlay JSON (`model-roles.user.json`, `ghost-text-state.json`) has atomic writes but no cross-process merge.
- Language servers run with the inherited environment; gopls needs `go` (wrapped), rust-analyzer uses the project's cargo from PATH.
