# Visuals evaluation: pi 1.3.0

[E] This is throwaway research only. All generated files, installations, runtime homes, configuration and projects are under `/tmp/pi-lab/visuals/`; the Nix repository was read but never changed. No real provider was configured. `[E]` means executed/observed here; `[C]` means read in package/runtime code or metadata; `[H]` means an unexecuted integration proposal.

## Verdict

- [E] **Closest integrated OMP presentation: `@nguyenquangthai/pi-omp-theme@1.0.26`, preset `omp`, plus `omp-dark`.** It actually renders compact Read calls, framed Edit/Bash cards, highlighted diffs with change counts and elapsed time, a rounded composer, and status in its top border. Adding `cost` to the status layout works without custom rendering code. `runs/top-omp/agent/settings.json` is the tested configuration.
- [C] Its maintenance cost is significant: rich message/tool presentation uses guarded host-prototype adapters, not `pi.registerToolRenderer`. The 15,105-line compiled entry contains compatibility probes and fallback logic. `allowCorePatches: false` does **not** mean the extension never decorates host methods; safe adapters are separately enabled by default.
- [E] **Simpler public-renderer alternative: `pi-tui-footer@1.4.2` plus `omp-dark`.** This is an open-tui-derived complete composition with rounded tool frames added through `registerToolRenderer`. It preserves the fixture's model-facing tool definitions and provides the polished rounded editor and header. Its default footer is two rows, not OMP's compact single row; tool cards retain native summaries and largely native diff coloring.
- [E] `pi-open-tui@0.3.11` alone is attractive but leaves native tool cards unchanged. A renderer-only adapter from pi-tui-footer coexists cleanly; the complete pi-tui-footer package avoids needing that adapter. Open-tui plus independently enabled Zentui Tool display also coexists.
- [E] `pi-topping-statusline` is a good isolated OMP-style **composer/status** transplant, not a drop-in footer-only add-on. Combining it with open-tui produces duplicate status/footer content and nested rails. Do not stack them indiscriminately.
- [E] Removing the user's local `visuals.ts` wrapper noticeably reduces clutter: `runs/zentui-clean/20-typing.png` retains the OpenCode-like rail editor and rich edit diff without the large custom workspace header and multi-line compliance footer. This is a viable OpenCode-oriented alternative, not a reason to retain the disliked whole baseline.

## Best evidence

- [E] Side-by-side against the user's actual OMP crop: [top-stacks-contact.png](top-stacks-contact.png).
- [E] All nine first-pass candidates, ordered open-tui / omp-theme / topping / topping-statusline / powerline / pretty / tui-footer / one-ui / current stack: [breadth-contact.png](breadth-contact.png).
- [E] Eight pair compositions: [pair-contact.png](pair-contact.png).
- [E] OMP active tools and diff: [runs/top-omp/07-tools.png](runs/top-omp/07-tools.png); completed answer/composer: [runs/top-omp/20-typing.png](runs/top-omp/20-typing.png); 80-column view: [runs/top-omp/40-narrow.png](runs/top-omp/40-narrow.png).
- [E] Simpler rounded tools prototype: [runs/top-open/07-tools.png](runs/top-open/07-tools.png), with adapter [prototypes/rounded-only.ts](prototypes/rounded-only.ts). Complete published equivalent: [runs/tui-footer-dark/20-typing.png](runs/tui-footer-dark/20-typing.png).
- [E] Reproduced disliked baseline: [runs/zentui/00-startup.png](runs/zentui/00-startup.png), [runs/zentui/20-typing.png](runs/zentui/20-typing.png). Baseline source/config copies are in `baseline/` and `runs/zentui/agent/`.
- [E] Reference images used here are copied into [references/](references/), including OMP and OpenCode crops. No screenshot/prototype linked above depends on an external artifact directory.

## Execution coverage and limits

[E] All nine candidates loaded and completed the standard `mkscenario.py` read/edit/bash/markdown/typing/expand/resize scenario on the pinned real pi 1.3.0 binary. Each first-pass run sent exactly four requests to the local scripted provider. No candidate was disqualified as broken or platform-incompatible. Twenty-two distinct scenario directories completed successfully; `run-summary.json` contains their driver results. The two finalist scenarios were additionally re-shot after correcting a capture step that originally ran before Enter.

[E] First pass used the user's Mona Lisa terminal palette and pi's `system` theme, except the current-stack baseline, which used its actual `managed-opencode` palette. The OMP-inspired candidate was deliberately configured with preset `omp` and automatic Titanium application off; this differs from its shipped Claude/Titanium default. All pair runs and finalist re-shoots used the theme evaluator's copied `omp-dark.json`.

[E] Captures include `00-startup`, `05-typed`, `10-after-turn`, `20-typing`, `30-expanded`, `40-narrow`; top-omp/top-open also include `07-tools` and `08-working`. All runs retain raw ANSI, textual screens, fixture requests and result JSON. Timings, cost and TPS are **synthetic fixture values**, not performance measurements.

[E] The standard project was not a Git repository, so real branch/PR decoration was not exercised. No authentication, real cloud access, real git repository updates or clipboard actions were exercised. Network behavior below is source review, not a packet-capture guarantee. Some Unicode/private-use glyphs render as missing glyphs in the lab image renderer; text/ANSI captures preserve the underlying characters.

## UI slot ownership

[C] `setHeader`, `setFooter` and `setEditorComponent` are single-owner slots; tool resolvers and keyed renderers are distinct composition mechanisms. `ui-audit.jsonl` in each run records actual intercepted slot setters/registrations. [prototypes/observe.ts](prototypes/observe.ts) is the observer; per-scenario wrappers are in `prototypes/`.

| Candidate | Header / footer / editor | Tools / message surfaces | Working / thinking / theme |
|---|---|---|---|
| open-tui 0.3.11 | [E] Owns all three; editor is a fresh `CustomEditor` subclass, not predecessor wrapping | [E/C] No tool renderer or tool replacement. Submitted user message stayed a native filled band despite package-description prompt-box wording; no built-in user-message renderer installation was found | [C] Embeds native working indicator in editor; hidden-thinking peek walks the live TUI component tree and sets a per-component label; resets public hidden label; telemetry is local turn data; no theme bundled |
| pi-omp-theme 1.0.26 | [E] Owns editor/footer/startup header and keyed startup/render widgets | [E/C] Guarded adapters decorate ToolExecutionComponent and message prototypes; no registerToolRenderer or tool-execution replacement observed; compact calls, rich diff and Bash exit/timing shown | [E/C] Owns working message/indicator and hidden-thinking label; auto-applies Titanium unless disabled; ships themes |
| topping 0.13.0 | [E] No header/footer/editor factory ownership in this run | [E/C] Custom prompt-message and entry renderers; input decoration can re-submit a custom message and marks original input handled; optional output styles alter model prompt sections | [E] Working message/indicator owner and completion-marker entry. [C] Not a visual-only semantics-neutral skin; offers setup commands that can install/remove sibling packages |
| topping-statusline 0.3.0 | [E/C] Wraps editor factory; directly patches native footer render to remove redundant rows rather than setFooter; leaves native header | [E] Native tools/messages unchanged | [C] Can host working/compaction progress; own status palette/graphs; 1s editor-owner reconciliation timer; no pi theme change |
| powerline-footer 0.20.2 | [E/C] Owns editor/footer and several keyed widgets; optional welcome overlay/header; predecessor is used only for autocomplete-provider composition, not render/input composition | [E] Native tool definitions/rendering unchanged. [C] Adds shell/stash/queue/input behaviors | [C] Working-vibe message owner; optional LLM generation, FX and auto-follow-up network features; no theme bundle |
| pretty-tui 0.3.0 | [E/C] No setEditorComponent in audit, but patches CustomEditor.prototype and numerous core message/Markdown/mouse prototypes; keyed activity widget; native footer | [E] Registers seven tool definitions, including grep/find/ls; these become model-visible, unlike default pi. [C] Wraps native execution objects for styling; also patches tool execution components | [E/C] Thinking/activity grouping and per-answer duration footer via persisted entry renderers; no theme bundle |
| tui-footer 1.4.2 | [E] Owns header/footer/editor; same general presentation as open-tui | [E/C] RoundedToolsManager registers a public tool-renderer resolver; no tools replaced; wraps existing calls/results and preserves native execution | [E/C] Open-tui-style peek/telemetry/working-in-editor; config key `roundedTools` defaults true; no theme bundle |
| one-ui 0.9.2 | [E] Owns header/footer/editor, plus widgets | [E/C] Extensive transcript prototype adapters; registers a write execution wrapper for diff metadata; custom message/entry renderers and Markdown transformer; fixture tool definitions still matched default pi | [C] Compact thinking, working-row implementation, two bundled cc themes; substantially larger dependency and behavioral surface |
| current stack: zentui 0.32.0 + visuals.ts | [E] Zentui owns editor; visuals.ts replaces header/footer; extra status lines consume vertical space | [E/C] Tool display uses registerToolRenderer, with explicit per-tool ownership consent. User messages use Zentui renderer decoration. No registerTool calls reached the baseline proxy | [E] Experimental thinking/working features disabled in reproduced config; managed-opencode theme selected |

[C] Relevant source anchors: open-tui `extensions/open-tui/index.ts:126-158,235-250`, `editor.ts:56-70,327-357`; tui-footer `extensions/rounded-tools.ts:247-280`; statusline `index.ts:268-326,360-411`; pretty `extensions/index.ts:770-777,1237-1241,2257-2260,4330-4351`; Zentui `extensions/zentui/tool-display/controller.ts:485-486`. All paths are below `pkgs/<candidate>/package/`.

## Pair tests and load order

| Pair and order | Executed result |
|---|---|
| open-tui then rounded-only resolver | [E] Clean coexistence: rounded editor/header/footer plus rounded native tool cards. Public renderer composition; no second editor/footer owner. `runs/open-rounded/` and `runs/top-open/` |
| open-tui then Zentui, editor/user-message disabled and footer native | [E] Clean slot coexistence: open-tui editor/header/footer, Zentui balanced tool summaries/diffs. `runs/open-zentui/` |
| Zentui tools only then topping-statusline | [E] Works: statusline provides composer box/graphs and Zentui provides tool cards. Native header remains; no open-tui footer duplication. `runs/zentui-status/` |
| open-tui then topping-statusline | [E] Statusline wraps open-tui's editor. Nested rails and duplicate open-tui status/footer remain; statusline cannot extract native stats from the custom footer. `runs/open-status/` |
| topping-statusline then open-tui | [E] Open-tui initially replaces it, then statusline's reconciliation wraps the new factory. Settled result still has redundant chrome; changing load order does not fix composition. `runs/status-open/` |
| open-tui then powerline | [E] Powerline's later editor/footer win; open-tui header/turn telemetry remain. The result has Powerline widgets and lacks open-tui's rounded editor. `runs/open-powerline/` |
| powerline then open-tui | [E] Open-tui's editor/footer win, but Powerline's keyed status/last-prompt widgets survive, producing duplicated status content. `runs/powerline-open/` |
| pretty-tui then topping-statusline | [E] Runs and shows pretty activity/per-answer footer plus statusline composer; this works partly because pretty patches the base editor prototype, not the factory slot. Not recommended because tool activation changes and global patches remain. `runs/pretty-status/` |

[E/C] **`ctx.ui.getEditorComponent()` wrapping is possible and exercised.** Statusline obtains the current factory, constructs its editor, binds/replaces that instance's `render`, and returns the same object, preserving its input API. It checks/re-wraps displaced owners every second. This proves factory composition, not arbitrary layout compatibility: renderers make different assumptions about border rows and autocomplete rows. Do not treat the getter as permission to safely combine every editor extension.

## What actually remains custom work

- [E] **Neutral prose and unscoped code:** applying omp-dark changes UI/highlight tokens but ordinary assistant prose and some code remain Mona Lisa yellow. None of these exercised UI configurations solves it. The theme evaluator owns this separate finding; this evaluation did not add a competing foreground patch.
- [E/C] **One compact OMP-like status row is already available:** pi-omp-theme's preset/status layout can do it, including cost. A custom footer is not inherently required. Topping-statusline instead distributes model/path versus token/context data across top and bottom borders. Open-tui/tui-footer default to two footer rows.
- [E/C] **Tool cards and highlighted diffs are already available:** do not build replacement tool execution for styling. Pi-tui-footer and Zentui provide public renderer approaches; pi-omp-theme provides the closest richer OMP-like layout using private guarded adapters. A custom resolver would only be needed for exact desired state-icon/summary/chrome details not matched by the selected existing renderer.
- [E/C] **OpenCode prompt/per-message combination is not furnished by either recommended stack.** Zentui has the rail/panel editor, and pretty-tui supplies a per-answer duration footer, but combining all visual packages globally is not a sound substitute for choosing owners. [H] A thin keyed entry-renderer extension could add a per-answer footer to the chosen stack without importing pretty-tui's tool replacements and global patches.
- [E] The open-tui and tui-footer runs did not decorate the submitted user message as the advertised rounded prompt box. [C/H] Use Zentui's independently switchable user-message surface if wanted, or implement that one surface rather than another all-UI owner; the independent user-message pairing itself was not executed here.
- [H] Pixel-level OMP/OpenCode parity still needs deliberate status/glyph/layout choices and terminal foreground correction. The actual screenshots, rather than npm descriptions, should determine acceptance.

## Supply-chain records

[C] **Exact names, versions, tarball URLs, sha512 `dist.integrity`, all scripts, non-peer dependencies, bin/license/unpacked size are recorded for every candidate and the shared primitive in [inventory.json](inventory.json).** Full registry documents and integrity-verified tarballs are retained in `pkgs/<candidate>/metadata.json` and `package.tgz`. Each tarball's downloaded SHA-512 was checked against the recorded registry integrity before extraction.

| Candidate | Exact version | Non-peer dependencies | Unpacked bytes |
|---|---:|---|---:|
| pi-open-tui | 0.3.11 | none | 230576 |
| @nguyenquangthai/pi-omp-theme | 1.0.26 | none | 653896 |
| @underactive/pi-topping | 0.13.0 | @underactive/pi-topping-primitives ^0.10.0 | 228238 |
| @underactive/pi-topping-statusline | 0.3.0 | @underactive/pi-topping-primitives ^0.10.0 | 305915 |
| pi-powerline-footer | 0.20.2 | none | 493324 |
| pi-pretty-tui | 0.3.0 | none | 622705 |
| pi-tui-footer | 1.4.2 | none | 138626 |
| pi-one-ui | 0.9.2 | jiti ^2.7.0, @shikijs/cli ^4.0.2, grok-mermaid ^0.2.2 | 1091831 |
| pi-zentui | 0.32.0 | none | 1395484 |
| @underactive/pi-topping-primitives | 0.10.0 | none | 817826 |

[C] All ten entries are MIT, have no package `bin`, and have no `install`, `postinstall` or `prepare` script. Other scripts are retained verbatim in inventory.json, including build/test/prepack/prepublish scripts; none were run. [E] No `.node` native add-on or standalone `.wasm` file was found in the extracted candidates/installed one-ui closure. [C] Shiki's JavaScript-packaged Oniguruma engine is distinct from a native Node add-on; pin its dependency closure, not a runtime download.

[E] For topping/statusline, primitives 0.10.0 was downloaded and linked directly under their isolated package directories; no npm lifecycle or pi package-management command was used. For one-ui, npm ran with `--ignore-scripts --omit=dev --legacy-peer-deps --no-audit --no-fund` and cache/home inside this area. Fifty runtime dependencies were installed. The exact runtime closure is [one-ui-runtime-lock.json](one-ui-runtime-lock.json); the full npm lock also contains uninstalled dev resolutions. Resolved direct runtime versions are jiti 2.7.0, @shikijs/cli 4.5.0 and grok-mermaid 0.2.3, with their registry metadata in [one-ui-direct-dependencies.json](one-ui-direct-dependencies.json). [C] A transitive regex-utilities package declares `prepare: npm test`; scripts remained disabled. Jiti and Shiki expose dependency-level CLI bins, not a pi-one-ui package bin.

## Runtime security / immutability review

| Candidate | Source-reviewed runtime behavior and integration controls |
|---|---|
| open-tui | [C] Reads project markers and package/runtime metadata; executes local git and detected language-runtime version commands with timeouts. Writes `open-tui.json` at first start if missing and on settings changes. Local turn telemetry only; no external transport/download found in reviewed runtime source. Pre-provision config in Nix; runtime executables must be explicitly available from nixpkgs. |
| pi-omp-theme | [C] Executes git status/branch/diff metadata reads; reads local Pi metadata/session openings for optional welcome view. Persistence command atomically writes global/project settings through a temporary file plus rename. No external network transport or telemetry implementation found in the reviewed bundle. Disable auto-theme/OSC background if managed elsewhere; keep readonlyTools false. |
| topping | [C] Reads/writes local settings, word packs and setup-check preference through primitives; custom entries persist in Pi's session log. `/topping-setup` can spawn `pi install`/remove for sibling packages when explicitly invoked: never expose/use that workflow in the immutable integration. No automatic install was observed. Default output style is neutral, optional styles are not. |
| topping-statusline | [C] Executes git/gh via `pi.exec`; watches Git HEAD; caches status; optional PR display may run gh and reach GitHub. **Set `segments.pr: false`** for no implicit cloud calls. Writes `pi-topping-statusline/settings.json` only through settings persistence. No runtime binary download found. Primitives supplies generic process spawning and atomic-settings helpers. |
| powerline-footer | [C] Broad side effects: persistent shell execution, shell/project history, stash and queue JSON/JSONL, settings and cached vibes/FX writes. Working vibes can call an LLM; non-USD cost fetches jsDelivr currency data; opt-in auto-follow-up calls api.typesafe.ai. The lab explicitly used no workingVibe and file mode, with welcome disabled. Too broad for a footer-only requirement; leave USD and all cloud features off if used. |
| pretty-tui | [C] Local config writes on mode changes; appends response/footer/activity entries to sessions; clipboard can delegate to host clipboard helpers on user action. No direct network/downloader found in reviewed extension code. Extensive global prototype patching plus registration of seven tools is the principal integration risk. |
| tui-footer | [C] Same local git/runtime-version inspection pattern as open-tui. Creates/saves `pi-tui.json`; `roundedTools` defaults true. No external telemetry/network/downloader found in reviewed extension source. The render-only adapter does no execution or filesystem operations itself. |
| one-ui | [C] Atomic local configuration writes, local git/runtime-version subprocesses and local session/agent metadata reads. Adds write-execution bookkeeping and project-file writes through its wrapper. Shiki/Mermaid operate locally; no downloader/network call found in the reviewed extension source. The 50-package runtime closure and extensive host patches make it needlessly broad for this task. |
| zentui | [C] Local config writes and git/runtime probes. Optional Codex quota collector calls `https://chatgpt.com/backend-api/wham/usage`; it is separately consented/gated and disabled in the reproduced and cleaned configs. Keep editor/footer codexQuota false. Experimental thinking decorates private host rendering; it was disabled here. |

[C] Source anchors: open-tui `config.ts:121-170`, `runtime.ts:124-139`, `git.ts:44-50`; omp-theme bundle `9525-9553,11671-11689,14783-14789`; topping `src/setup-command.ts:65-96`; statusline `src/context.ts:218-230,292-329`; powerline `auto-follow-up.ts:1-15`, `currency-rates.ts:22-77`, `working-vibes.ts:210-212`, `bash-mode/shell-session.ts:134-193`; pretty `extensions/index.ts:662-664,4297-4303`; zentui `extensions/zentui/codex-quota.ts:10,134-174`. Paths are relative to the relevant package directory under `pkgs/`.

## Recommended immutable pins

[C] Primary: `@nguyenquangthai/pi-omp-theme@1.0.26` — `sha512-JMXETWk+4Zdz5FACxJYbqBtySPNZH/dV1i2DUKFgtuS1jQ0w6wpzMOQZ2XDTSGUcLH3KYgtV6csa/92RRyyzAw==`.

[C] Simpler alternate: `pi-tui-footer@1.4.2` — `sha512-aCSfWYzcWNS9ngDuXXuNsxhjln+usD64jwIBqvMmcojvYA9bi+U9ZJlJC0LzhJpMxFEtlO/pq92X/HS6rTemfA==`.

[C] If retaining specifically approved open-tui: `pi-open-tui@0.3.11` — `sha512-/uT5QZTFl1/GyO4Nre3u1cIOBBgDsX96ze3F0doxNKi4EsKvOqgTovRpYqbLASKTfljs612bH7I2J1wZQJzTcw==`; pair it with a **single** chosen tool-renderer owner, not another complete UI package.

[H] Integration should fetch these tarballs as fixed-output Nix inputs, load their declared entry points/themes directly, pre-provision settings, and disable runtime package-management controls. Do not run `pi install`, npm lifecycle scripts, language/runtime installers, or cloud enrichment merely to obtain visual polish.

## Residual risks

[E/C] Full keyboard selection/autocomplete, settings toggling/reload, changing sessions, real Git/PR state, real image tool results and nonstandard third-party tool renderers were not comprehensively exercised. Source guarded fallbacks are not evidence that all of those work. [H] Before production selection, the coordinator should manually exercise those paths with the final LSP/ghost/routing extensions and the user's actual terminal font. The 1s statusline editor reconciliation and global prototype decorators deserve particular attention; load-order screenshots already demonstrate why one visual owner per slot matters.

## Follow-up

[E] Eight additional real-pi scenarios completed: status composition in border/above/inline/boxed variants, three editor-wrapper comparisons, and the reload/streaming-resize test. Results are in [follow-up/run-summary.json](follow-up/run-summary.json). This section **supersedes the initial assumption that `secondary: ["extension_statuses"]` is sufficient in OMP border mode**.

### 1. Extension status composition: primary integration blocker

- [E] Fixture [follow-up/status-fixture.ts](follow-up/status-fixture.ts) publishes `lsp`, `ast-grep`, and `managed-routing` with distinct ANSI truecolors. In the stock `omp` border composition, **none of the three statuses appears**, at either 120 or 80 columns: [120](runs/follow-status/01-status-120-readonly.png), [80](runs/follow-status/02-status-80-readonly.png). Listing `extension_statuses` in the border's primary group also did not expose them: [inline attempt](runs/follow-status-inline/01-short-120.png).
- [C] The segment is named **`extension_statuses`**, not `status`. The aggregate sorts entries by status key and joins values with spaces: bundle `9800-9804`. A per-key configuration also exists through `statusLine.customItems[]`, but the editor border constructs only built-in segments, not the custom-segment map (`10523-10527` versus `11442-11456`).
- [C] There are two relevant implementation boundaries: `statusRowVisible` suppresses **both** primary and secondary widget rendering whenever placement is `border` and the editor hosts its status (`11420-11421,11475-11478`); and the real Pi adapter's `app.sessionStart` call supplies no `extensionStatusProvider` (`14915-14936`). The standalone status widget can read live footer statuses through `effectiveSnapshot` (`11506-11515`), but that enriched snapshot is not passed to the editor border.
- [E] Setting placement `above` makes all three short values visible, ordered **ast-grep, LSP, routing**, on a separate row **below the editor**: [120](runs/follow-status-above/01-short-120.png), [80](runs/follow-status-above/02-short-80.png). However, leaving the OMP dock editor enabled also duplicates the primary model/path/cost presentation: one widget above the editor and one embedded in its border.
- [E] Switching the editor to `boxed` avoids that duplicated embedded status and gives a standalone primary row plus the separate status row: [120](runs/follow-status-boxed/01-short-120.png), [80](runs/follow-status-boxed/02-short-80.png). Despite explicitly requesting frame `rounded`, this style renders rules rather than the original rounded dock. Tested compromise configuration: [follow-up/status-visible-settings.json](follow-up/status-visible-settings.json). It is not exact OMP parity.
- [E/C] Long/multiple statuses are **not wrapped or ellipsized individually**. In the tested aggregate, the entire combined status segment disappears when it exceeds the row width, at both 80 and 120 columns: [long 80](runs/follow-status-above/03-long-80.png), [long 120](runs/follow-status-above/04-long-120.png). `renderStatus` rejects an over-wide secondary candidate wholesale (`9958-9963`). See [follow-up/status-results.json](follow-up/status-results.json).
- [E] **ANSI colors are preserved in the real output stream.** The exact magenta, green and cyan SGR sequences from the fixture remain around their corresponding values; [follow-up/status-ansi-proof.json](follow-up/status-ansi-proof.json) records all three true. The lab image renderer remaps canonical xterm RGB colors to the Mona Lisa palette, so its magenta/green appearance is not a faithful color measurement; the raw ANSI is decisive here.
- [H] Production primary selection needs an explicit status-composition fix or a small independently keyed status widget; the tested `secondary` setting alone is insufficient. Fixing only the secondary-widget visibility gate would still leave the long-status all-or-nothing overflow behavior. Do not silently ship a visually polished primary stack that hides LSP/routing status.

### 2. Declarative configuration, complete key catalog, and read-only symlinks

[C] The extension's own settings schema is the object **`piOmpTheme`** with `schemaVersion: 1`, inside Pi settings JSON. There is no separate `pi-omp-theme.json` required by this package. Validation is implemented in the bundle, not a separately shipped JSON Schema document. Unknown fields/invalid values produce bounded diagnostics and are ignored. Missing schemaVersion is accepted as v1-shaped input with a diagnostic; unsupported schema versions are ignored/protected from persistence (`9061-9097`).

[C] Main settings sources, lowest to highest precedence: defaults/coordinated preset; `getAgentDir()/settings.json` (`PI_CODING_AGENT_DIR` in this lab, normally `~/.pi/agent/settings.json`); trusted-project `<cwd>/.pi/settings.json`; environment overrides; session mutations. Project settings are not loaded without project trust. The namespace is `piOmpTheme` in both files (`9101-9112,9557-9561,14455-14482`).

[C] Complete supported configuration leaves are also machine-readable in [follow-up/config-contract.json](follow-up/config-contract.json):

- Root: `schemaVersion`, `enabled`, `readonlyTools`, `preset`, `placement`, `debug`.
- `startup`: `mode`, `showResources`, `alwaysExpanded`.
- `statusLine`: `enabled`, `separator`, `layout.left`, `layout.right`, `layout.secondary`, `disabledSegments`, `customItems`, `bottomMargin`, `contextBarWidth`. Each custom item accepts `id`, `statusKey`, optional `label`, `priority`, `placement`.
- `editor`: `enabled`, `style`, `frame`, `showMetadata`, `hint`.
- `messages`: `enabled`, `assistantPrefix`, `specialBlocks`, `hideThinkingLabel`, `hideInterimText`, `assistantMarker`, `thinkingSummary`, `interruptHint`.
- `tools`: `enabled`, `style`, `maxCollapsedLines`, `maxExpandedLines`, `dimOutput`, `showElapsed`, `collapseAfterTurn`, `batchQuietCalls`, `chrome`, `collapseMutatingTools`, `editSummary`.
- `theme`: `nerdFonts`, `shimmer`, `workingElapsed`, `workingTokens`, `cacheHighlight`, `sessionAccent`, `terminalBackgroundSync`, `autoApply`, `colors`, `glyphs`.
- `widgets.hide`; `compatibility.allowSafePatches`, `allowCorePatches`, `preferExistingEditor`, `preferExistingFooter`.

[C] Enumerations: presets `default|minimal|compact|full|ascii|native|claude|claude-code|omp`; placement `above|below|border`; startup mode `off|compact|overlay`; editor style `compact|boxed|dock|native`; frame `auto|halfblock|line|solid|outline|rounded|claude|native`; nerdFonts `auto|on|off`; shimmer `classic|kitt|off`; terminalBackgroundSync `auto|on|off`; tool chrome `boxed|light|inline`. Color/glyph maps accept string values, layout/hidden/disabled lists accept strings, numeric budgets/margins/widths accept finite nonnegative numbers and are normalized/clamped. Source catalog: `8654-8738`.

[C] Environment inputs: `PI_OMP_THEME_DISABLED`, `PI_OMP_THEME_NERD_FONTS`, `PI_OMP_THEME_EDITOR`, `PI_OMP_THEME_THEME`, `PI_OMP_THEME_OSC11`, `PI_OMP_THEME_DEBUG`, `PI_OMP_THEME_STATUS` (`8963-9012`). CLI surface/authorization switches documented by the package: `--pi-omp-theme-core-patches`, `--pi-omp-theme-message-assistant`, `--pi-omp-theme-message-special-blocks`, `--pi-omp-theme-tools`, `--pi-omp-theme-readonly-tools <true|false>`, `--pi-omp-theme-ascii`. Session `/pi-omp-theme set ...` changes memory; explicit `persist global|project ...` is the disk-writing command.

[C] The bundled theme-discovery helper additionally reads the active theme's `sourcePath`/`definition.sourcePath` JSON (`name`, `vars`, `colors`, `extras`, `export`). Fallback discovery reads **conventional** `$HOME/.pi/agent/settings.json` and `<cwd>/.pi/settings.json` keys `theme`, `packages`, `extensions` (package objects use `source`), plus JSON themes below `$HOME/.pi/agent/themes`, `<cwd>/.pi/themes`, theme directories in local package paths, and `themes` directories recursively within conventional `.pi/agent/git` / project `.pi/git` checkouts to bounded depth. It also probes host-package built-in theme directories relative to the extension and cwd (`620-738`). These fallback conventional-home paths are distinct from the main getAgentDir-based configuration path. In every lab run HOME was isolated under this area.

[E] Exact minimal tested JSON for preset `omp`, no auto-theme, no OSC background writes, readonlyTools false, and configured pi/model/path/git/cost/context status groups: [follow-up/minimal-settings.json](follow-up/minimal-settings.json). It uses the editor's embedded context gauge; `context_pct` is explicitly suppressed inside the rounded border renderer because the gauge supplies the percentage/window (`10519-10538`). Thus a literal arrow-delimited ctx% segment is not how this preset is implemented. `git` was configured but a real Git repository was not introduced under the lab's no-git-writes rule, so actual branch decoration remains source-reviewed rather than exercised.

[E] That JSON was loaded through an agent `settings.json` symlink to [follow-up/immutable/settings.json](follow-up/immutable/settings.json), with target mode **0444** and containing directory **0555**, as uid 1000. Loading, status changes and a model turn completed without exceptions/repeated write-failure toasts. The exercised raw streams contain **zero OSC 11 setter sequences**; [follow-up/runtime-scan.json](follow-up/runtime-scan.json) records the scan.

[E] **Explicit Save does not preserve the Home Manager symlink.** `/pi-omp-theme persist global set statusLine.contextBarWidth 9` succeeded by creating a temporary file beside the symlink and atomically renaming over it. The agent's settings.json became a regular file with the saved value; the 0444 target in the 0555 directory stayed unchanged. Evidence: [follow-up/readonly-save-result.json](follow-up/readonly-save-result.json), [save screenshot](runs/follow-status/07-persist-global.png), [settled screenshot](runs/follow-status/08-persist-settled.png). [C] This follows `writeAtomic` (`9545-9552`); a truly unwritable *symlink-parent* directory would instead reach a caught one-shot `settings write failed` toast (`9493-9504`), but that different permission arrangement was not executed. [H] A managed integration should prevent/disable persistence, or clearly document that it replaces managed symlinks; target read-only mode alone is not protection.

### 3. Editor-wrapper coexistence

[E] The **28-line** [follow-up/ghost-probe.ts](follow-up/ghost-probe.ts) was loaded as a separate extension **after** each UI extension. It gets the existing editor factory, returns the same editor instance after wrapping render, inserts a dim ` ‹ghost›` on the `probe words` cursor-text row, and removes the corresponding right padding to keep chrome in width. It is a deterministic rendering probe, not a completion implementation or a general Unicode/cursor algorithm.

[E] The marker rendered inside the composer at 120 and 60 columns for all three plugins; no renderer exception occurred. [Contact sheet](follow-up/wrappers-contact.png). Individual evidence:

- pi-omp-theme: [120 after 3s](runs/follow-wrapper-omp/01-wrapper-120-after-3s.png), [60](runs/follow-wrapper-omp/02-wrapper-60.png).
- pi-tui-footer: [120 after 3s](runs/follow-wrapper-tui/01-wrapper-120-after-3s.png), [60](runs/follow-wrapper-tui/02-wrapper-60.png).
- pi-open-tui: [120 after 3s](runs/follow-wrapper-open/01-wrapper-120-after-3s.png), [60](runs/follow-wrapper-open/02-wrapper-60.png).

[E] Each `wrapper-audit.jsonl` reports `ours: true` immediately after installation and again 2500ms later, and subsequent narrow screenshots still contain the marker. [C] pi-omp-theme has **no topping-statusline-style 1s factory-reclamation loop**; its editor installer updates live instances and restores the predecessor on disposal only if it still owns the outer factory (`10655-10717`). The user-visible 1s-type timers in this bundle are working/tool animations, not editor ownership reconciliation. This experiment proves simple late wrapping, not real completion cancellation, draft preservation through reload, or arbitrary-width input semantics.

### 4. Submitted user-message panel

[E] **None of these three stock tested configurations supplies the requested left-bar/boxed submitted prompt.** All retain Pi's native full-width background-filled user-message band, without the OpenCode heavy left bar or rounded enclosing frame. Screenshots deliberately keep the submitted prompt visible:

- [pi-omp-theme](runs/follow-wrapper-omp/03-submitted-120.png).
- [pi-tui-footer](runs/follow-wrapper-tui/03-submitted-120.png).
- [pi-open-tui](runs/follow-wrapper-open/03-submitted-120.png).

[E/C] The full-width fill is present and follows omp-dark's user-message background; the desired extra message chrome still requires an independently selected message decorator or an adapter. The open-tui package description is not evidence that this capability is actually installed in version 0.3.11.

### 5. Reload, resize, and expand/collapse robustness

[E] Scenario [scenarios/follow-robustness.json](scenarios/follow-robustness.json) performs `/reload` twice before the turn, then 120→60→120 resizing during the streamed turn and Ctrl+O expansion/collapse both during and after streaming. It completed with exactly four fixture requests, no process exit and no driver failure.

[E] Both post-reload screenshots contain one welcome/header instance, not two: [reload one](runs/follow-robustness/01-reload-one.png), [reload two](runs/follow-robustness/02-reload-two.png). The final completed view contains a single composer with no observed orphan status widget: [final collapsed](runs/follow-robustness/08-final-collapsed.png). The raw stream scan found no TypeError, RangeError, ReferenceError, unhandled-rejection or settings-write-failed message.

[E] **One transient rendering blemish was observed at the narrow streaming resize:** the Bash card shows a repeated trailing `fmt.Println`/closing-brace/`done` fragment in [streaming 60](runs/follow-robustness/03-streaming-60.png). It is not present as an extra final widget after returning to 120 columns: [streaming 120](runs/follow-robustness/04-streaming-120.png), [final collapsed](runs/follow-robustness/08-final-collapsed.png). [H] This may be a host/extension redraw or PTY-emulator resize artifact; this experiment does not distinguish them. It would be inaccurate to claim blemish-free resizing. Raw redraw repetitions alone are not counted as duplicate persistent widgets.

[E/C] Follow-up conclusion: late editor wrapping and declarative read-only *loading* work; status visibility and symlink-preserving persistence are **not** production-safe as initially assumed. [H] Keep pi-omp-theme as the primary visual candidate only with explicit decisions for status aggregation/overflow, submitted-user chrome, and managed-settings persistence.
