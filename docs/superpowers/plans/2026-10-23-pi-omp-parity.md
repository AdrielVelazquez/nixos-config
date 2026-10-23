# Pi omp/opencode parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make the Nix-managed Pi 1.3.0 look and behave like omp/OpenCode: omp-style UI, working LSP, inline ghost-text word completion, omp-style role routing with a `/models` screen.

**Architecture:** One slice per concern, each in its own module (`pi-ui`, `pi-lsp`, `pi-ghost`, `pi-model-roles`) that appends to `local.pi.extraSettings.extensions`; extension entries are generated `pkgs.writeText` files that import `dotfiles/pi/extensions/*.ts` and pass JSON options (the pattern already used by `pi-capabilities.nix` and `pi-routing.nix`). Slices touch disjoint files; shared files are wired once in the skeleton commit and finalised by the coordinator.

**Tech Stack:** Nix (Home Manager, `buildNpmPackage`, `importNpmLock`, `fetchurl`), Pi 1.3.0 (`@earendil-works/pi-coding-agent`, `pi-tui`), TypeScript run by jiti, Node 24 `node:test`, Python 3 + pyte for PTY checks.

**Spec:** `docs/superpowers/specs/2026-10-23-pi-omp-parity-design.md`. Evidence: `docs/reviews/2026-10-23-pi-omp-parity-evaluation/` (reports include pins, exact configs, risks). Throwaway prototypes and lab runs live under `/tmp/pi-lab/` for this session only; port from them, never import from them.

## Global Constraints

- Target config: `cachyos-framework13` (flake output `homeConfigurations.cachyos-framework13`, user `adriel-cachyos`). Validation host: this CachyOS machine. Verification per slice: `rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath` and `rtk nix build --no-link .#checks.x86_64-linux.<your checks>`.
- Prefix shell commands with `rtk`. Use `nix shell nixpkgs#<pkg> -c ...` for tools that are not installed (node is NOT installed globally; python with pyte/pillow: `nix build --impure --no-link --print-out-paths --expr 'with import (builtins.getFlake "nixpkgs") {}; python3.withPackages (p: [ p.pyte p.pillow p.fonttools ])'`).
- NEVER run `home-manager switch`, `nixos-rebuild`, `system-manager switch`, `pi install`, or write to the real `~/.pi`, `~/.omp`, `~/.config`. Throwaway state only under `$TMPDIR` or `/tmp`.
- Work only in your own worktree/branch; commit in small logical commits (`feat(pi): ...`, `test(pi): ...`, `docs(pi): ...`). Do not edit shared files except where your task lists them.
- Pins: every npm tarball is a fixed-output `fetchurl` whose SRI sha512 you compute with `nix store prefetch-file --hash-type sha512 <tarball url>` AND compare with `npm view <pkg>@<ver> dist.integrity` (registry JSON). Never copy a hash from a report. Packages with non-peer dependencies use a vendored `package-lock.json` + `importNpmLock` + `--ignore-scripts --legacy-peer-deps` exactly like `packages/pi-subagents.nix`; a source patch is a separate file named `{package}-path-{reason}.nix` (see `pi-subagents-path-required-mcp.nix`).
- No runtime downloads, telemetry, cloud calls or lifecycle scripts. Language servers/word lists/binaries come from nixpkgs.
- New files must be `git add`ed before `nix eval` (flakes ignore untracked files); stage only your own files.
- Every pin/exception: write `docs/todo-fragments/<slice>.md` in the TODO.md entry format (reason, upstream link/commit, how to check obsolete, target config). The coordinator merges fragments into TODO.md.
- Docs: write your slice's user-facing doc as `docs/pi-<slice>.md` (what it does, config, limits, verification command). The coordinator folds links into `docs/pi.md`.
- Tests: unit tests are `node:test` `.mjs` files importing the extension `.ts` directly (style of `tests/pi/primary-routing.mjs`); PTY tests drive real pi with pyte (style of `tests/pi/capability-ui.py`; the session lab `/tmp/pi-lab/lab.py` shows a scripted OpenAI-compatible fake provider, OSC color replies and PNG rendering). Wire every test into a Nix check in your own `checks/pi-<slice>.nix` (same shape as `checks/pi.nix`).

## Review Focus

- Non-TUI modes (`pi -p`, `--mode json`, `--mode rpc`, subagent children with `PI_SUBAGENT_CHILD=1`): every new extension must be a harmless no-op or must work headless; no exceptions on stderr.
- `/reload` twice and `/new`: no duplicated editor wrappers, listeners, widgets or prototype patches; shutdown restores anything patched.
- Read-only Home Manager files: a symlinked/read-only config or settings file never crashes an extension or spams toasts; writable state goes to separate overlay files (mode 0600, atomic rename).
- Narrow terminals (80 and 40 columns) and wide/emoji/CJK input never overflow a rendered line.
- Untrusted project (`--no-approve`): project files can never add LSP servers, roles, or word lists.
- Failure visibility: missing server binary, missing word list, invalid overlay JSON, unavailable role model → visible, specific message and safe degradation; never silently substituting another model or provider.

## File Structure

| Path | Slice | Responsibility |
|---|---|---|
| `packages/pi-omp-theme.nix`, `packages/pi-terminal-theme.nix` | ui | pinned tarballs via `pi-extension-source.nix` |
| `dotfiles/pi/themes/omp-reference.json`, `omp-dark.json` | ui | strict-schema truecolor themes |
| `dotfiles/pi/extensions/neutral-foreground.ts` | ui | default-foreground adapter |
| `modules/home-manager/pi-ui.nix`, `checks/pi-ui.nix`, `tests/pi/ui-*.{mjs,py}` | ui | wiring + checks |
| `packages/pi-lsp.nix`, `packages/pi-lsp/{package.json,package-lock.json}`, `packages/pi-lsp-path-push-diagnostics.nix` (+ `.patch`) | lsp | patched pinned plugin |
| `dotfiles/pi/extensions/lsp-status.ts`, `modules/home-manager/pi-lsp.nix`, `checks/pi-lsp.nix`, `tests/pi/lsp-*` | lsp | status bridge, servers, checks |
| `dotfiles/pi/extensions/ghost-text.ts`, `ghost-core.ts`, `packages/pi-ghost-wordlist.nix`, `modules/home-manager/pi-ghost.nix`, `checks/pi-ghost.nix`, `tests/pi/ghost-*` | ghost | engine, editor wrapper, word list |
| `dotfiles/pi/extensions/model-roles.ts`, `role-core.ts`, `modules/home-manager/pi-model-roles.nix`, `modules/home-manager/pi-routing.nix` (modify), `checks/pi-model-roles.nix`, `tests/pi/role-*`, `tests/pi/model-roles-*` | roles | router, UI, Nix options, subagent role files |
| `docs/pi-gap-analysis.md`, `docs/pi.md`, `TODO.md`, `users/adriel-cachyos/default.nix`, `checks.nix` | coordinator | integration |

## Option contracts (the interface between slices and the coordinator; implement exactly)

`local.pi.ui`: `enable` (mkEnableOption); `package` (pi-omp-theme derivation, `passthru.packageRoot`); `terminalThemes.enable` (bool, default true: add pi-terminal-theme's `themes/` dir to `settings.themes`); `theme` (str, default `"omp-reference"`); `settings` (json attrs merged over managed defaults into `settings.piOmpTheme`); `neutralForeground.enable` (bool, default true); `entries` (readOnly attrsOf str: entry file store paths, keys `ompTheme`, `neutralForeground`).
`local.pi.lsp`: `enable`; `package`; `status.enable` (bool, default true); `servers` (attrsOf submodule: `enable` bool default true, `package` nullOr package, `command` str, `args` listOf str, `languages` listOf {extensions, languageId}, `rootMarkers` listOf str, `requireRootMarker` bool default false, `initializationOptions` json, `settings` json, `environment` attrsOf (nullOr str), `runtimeInputs` listOf package) with defaults for every server in D5; `timeouts` (json); `entries`.
`local.pi.ghostText`: `enable`; `wordList` (path; default the `pi-ghost-wordlist` file); `entries`.
`local.pi.modelRoles`: `enable`; `roles` (attrsOf (nullOr str); omp selector syntax `provider/model[:thinking]`, comma alternatives, `@role` aliases); `fallbackChains` (attrsOf (listOf str), default `{}`); `modelFallback` (bool, default false); `cooldownMs` (int, default 60000); `cycleOrder` (listOf str, default `["smol" "default" "slow"]`); `autoTitle` (bool, default true); `compactionRole` (nullOr str, default null = stay on the active model); `planMode.readOnly` (bool, default false); `taskAgents` (attrsOf str: pi-subagents role file name → selector, resolved at eval time to `model:`/`thinking:` frontmatter); `entries`. Removes `local.pi.routing.agents`/`autoTitle`; `local.pi.routing` keeps `enable`, `package`, MCP tool lists.

---

### Task 1: UI slice (branch `feat/pi-omp-parity-ui`)

**Files:** see table. Modify `modules/home-manager/pi-capabilities.nix` (remove `editor`/zentui/visuals, keep `ast`, `web`), `dotfiles/pi/extensions/ast-readonly.ts` (shorter status text so all footer statuses fit 80 columns), `tests/pi/capabilities-contract.mjs`, `tests/pi/capability-ui.py`, `checks/pi.nix` (drop `editor.enable`/`zentui.json` references). Delete `packages/pi-zentui.nix`, `dotfiles/pi/extensions/visuals.ts`, `dotfiles/pi/themes/managed-opencode.json`.
**Prototype sources:** `/tmp/pi-lab/theme/{omp-reference.json,omp-dark.json,neutral-foreground.ts}`; tested config `/tmp/pi-lab/decision/runs/omp-theme/agent/settings.json`; reports `visuals-report.md`, `theme-report.md`.
**Interfaces:** produces `local.pi.ui` (contract above). Settings it must emit: `theme`, `themes` (omp themes + optional pi-terminal-theme dir), `quietStartup = "header"`, `piOmpTheme` = `{schemaVersion 1; preset "omp"; readonlyTools false; theme {autoApply "off"; terminalBackgroundSync "off"}; statusLine.layout {left [pi model_effort path git cost]; right [context_pct]; secondary [extension_statuses]}; placement "above"; editor {style "boxed"; frame "rounded"}; startup.mode "off"; compatibility.preferExistingEditor false}` merged with `ui.settings`; extensions `[ompTheme entry, neutralForeground entry]` in that order.

- [ ] **Step 1: pins.** `packages/pi-omp-theme.nix` (`@nguyenquangthai/pi-omp-theme@1.0.26`, entry `dist/extensions/pi-omp-theme.ts`) and `packages/pi-terminal-theme.nix` (`pi-terminal-theme@0.2.0`) via `pi-extension-source.nix`; verify hashes per Global Constraints.
- [ ] **Step 2: themes.** Port both JSON themes; failing test `tests/pi/ui-contract.mjs::themes_are_strict_schema_valid` loads each through real pi (`pi --theme <file> --use-theme <name> --mode json -p x` against a fake provider, or the exported theme loader) and asserts no theme diagnostics; then make it pass.
- [ ] **Step 3: `neutral-foreground.ts`.** Export `default function (pi)`; patch `Markdown.prototype.render`/`CustomEditor.prototype.render` only if the originals are functions, never double-wrap (module-level guard), reread `ctx.ui.theme` at render time, restore on `session_shutdown`, no-op when `ctx.mode !== "tui"`. Unit tests (`tests/pi/ui-neutral-foreground.test.mjs`): reopens text color after `\x1b[0m`/`\x1b[39m`, keeps explicit fg, idempotent across two factory calls, restores originals.
- [ ] **Step 4: module + cutover.** Implement `pi-ui.nix`; remove zentui/visuals/managed theme; update `pi-capabilities.nix`, contract test, PTY test (assert: omp status row, rounded prompt, three statuses visible at 120 and 80 columns, theme name, no extension errors, settings files stay symlinks).
- [ ] **Step 5: PTY check.** `checks/pi-ui.nix` runs the PTY test in the Nix sandbox (pyte, pillow, DejaVu/Maple font as in `pi-capabilities-ui`) and the contract tests; add `--mode json`/`-p` smoke proving no output on stderr.
- [ ] **Step 6: docs + todo fragment.** `docs/pi-ui.md` (what ships, how to switch themes, persist-command caveat: it replaces the managed `settings.json` symlink; neutral-foreground coupling), `docs/todo-fragments/ui.md` (pi-omp-theme pin, pi-terminal-theme pin, neutral-foreground adapter, private-adapter risk).
- [ ] **Step 7: verify + commit.** `nix eval` of the target; `nix build --no-link .#checks.x86_64-linux.pi-ui`; screenshot via `/tmp/pi-lab/lab.py` of the real generated agent dir saved as `docs/assets/pi-omp-parity/ui.png` (<300 KB).

### Task 2: LSP slice (branch `feat/pi-omp-parity-lsp`)

**Prototype sources:** `/tmp/pi-lab/lsp/{ian-push-diagnostics.patch,ian-patched-status-bridge.ts,recommended-settings.json,runtime/package-lock.json}`, `lsp-report.md`.
**Interfaces:** produces `local.pi.lsp` (contract). Emits `settings.lsp` (`includeHintDiagnostics false`, timeouts, one entry per enabled server using absolute store paths) and extension entry that imports the patched package's `src/index.ts` through `createLspStatus(pi, upstream)` from `dotfiles/pi/extensions/lsp-status.ts` (Proxy captures the `lsp_status` tool, calls only `ctx.ui.setStatus("lsp", ...)` on `session_start`/`tool_result`/`agent_end`, clears on shutdown; never `setFooter`).
Servers (all default enabled, from the repo's pinned nixpkgs): `gopls` (+ `go` on its PATH via wrapper, `GOTOOLCHAIN=local`, `GOTELEMETRY=off`, settings from `dotfiles/nvim/lsp/gopls.lua`: staticcheck, gofumpt, analyses), `typescript-language-server` (+ `typescript_5` `tsserver.js` path in `initializationOptions.tsserver.path`, `disableAutomaticTypingAcquisition`; NOT typescript 7), `nixd`, `basedpyright-langserver` (+ settings from `dotfiles/nvim/lsp/basedpyright.lua`), `ruff server`, `pyrefly lsp`, `bash-language-server` (+ `shellcheck`), `rust-analyzer` (uses the project's cargo from PATH; no toolchain closure), `lua-language-server`, `marksman server`, `vscode-json-languageserver --stdio`, `terraform-lsp`, `zls`.

- [ ] **Step 1: package.** `packages/pi-lsp.nix` (tarball `@ian-pascoe/pi-lsp@0.15.1`, vendored lock from the prototype's resolved install, `--ignore-scripts --legacy-peer-deps`), patch in `packages/pi-lsp-path-push-diagnostics.nix` applying `ian-push-diagnostics.patch` at build; failing check first (`checks/pi-lsp.nix` asserts the patched hunk exists and package has no lifecycle scripts), then pass.
- [ ] **Step 2: bridge unit tests** (`tests/pi/lsp-status.test.mjs`): captures `lsp_status`; label formats (`LSP gopls ● · typescript ●`, `N configured` when idle); clears on shutdown; never calls `setFooter`; tolerates a missing `lsp_status`.
- [ ] **Step 3: module.** `pi-lsp.nix` renders servers/settings; assertions fail when an enabled server has no executable; wrapper derivations for gopls.
- [ ] **Step 4: behavior check with real servers in the Nix sandbox** (`tests/pi/lsp-diagnostics.py` or `.mjs`; run real pi in `--mode json -p`/PTY against a scripted fake provider): (a) Go: `write` a file with a type error → the NEXT request's tool result contains the gopls diagnostic; repair → explicit clean result; (b) TS the same; (c) `lsp_goto_definition`/`lsp_find_references`/`lsp_hover`/`lsp_rename` (preview) return real results; (d) with `--no-approve` a project `.pi/settings.json` cannot add a server; (e) missing server binary → visible failure text, not a crash. Delayed-diagnostics freshness (server publishes 9 s late) must not attach stale errors after repair.
- [ ] **Step 5: docs + todo fragment** (`docs/pi-lsp.md`: servers, PATH behavior, how to disable one, the patch and when to drop it; fragment records the 15-line patch exception and upstream issue/PR link to open or check).
- [ ] **Step 6: verify + commit** (`nix eval`, `nix build` the `pi-lsp` check; screenshot of the footer status).

### Task 3: Ghost-text slice (branch `feat/pi-omp-parity-ghost`)

**Prototype sources:** `/tmp/pi-lab/ghost/{ghost-text.ts,ghost-core.ts,ghost-core.test.ts,recommended-agent/,dictionary-pin.json}`, `ghost-report.md` (includes omp's exact gates, keys and ranking).
**Interfaces:** `createGhostText(pi, { wordList: string })` exported from `dotfiles/pi/extensions/ghost-text.ts` (default export may call it with env `PI_GHOST_WORDLIST` for the lab). `packages/pi-ghost-wordlist.nix` = derivation copying only `share/dict/wamerican.35` from `pkgs.scowl` (sha256 of the file: `b31d847c962c964791909717a0b85ed977a6cd12b468687564291efc5b796e7a`, assert it). Module `pi-ghost.nix` generates the entry and must order it after `local.pi.ui` entries. State: `<agent-dir>/ghost-text-state.json` (0600, atomic, debounced).

- [ ] **Step 1: port + clean** engine and wrapper; keep: mounting in `resources_discover` by wrapping `ctx.ui.getEditorComponent()` (same instance; `CustomEditor` fallback), painting at pi's cursor/fake-cursor APC markers, Tab accepts with trailing space, Right accepts without, Esc/typing dismisses, hidden while native autocomplete is open, omp prose gates (end of line, `[\p{L}\p{M}']+` word, no `\ / @ _ = : { } [ ] < >`/digits/camelCase, masked fences/inline code/HTML, `/` and `->`/`=>` lines, buffer caps 20,000/1,000), threshold 0.15, accept/reject feedback learning, learning from transcript and `message_end`, bounded state (30k/40k/40k/10k/4096).
- [ ] **Step 2: unit tests** `tests/pi/ghost-core.test.mjs` (port the 12 plus: missing word list → no suggestion and one visible notice; corrupt state file ignored; state mode 0600).
- [ ] **Step 3: PTY check** `tests/pi/ghost-pty.py` with a dependency-free fake visual owner (custom `setEditorComponent` extension) in both load orders: suffix painted after the cursor, Tab accepts, each gate shows nothing (`/mo`, `@src/`, inside ``` fence, mid-word cursor, camelCase), 40-column and CJK/emoji input, `/reload` twice without double wrapping, zero provider requests. (The combined check with pi-omp-theme runs in the coordinator integration.)
- [ ] **Step 4: module, docs (`docs/pi-ghost-text.md`: omp parity table including what is NOT matched: web prior, SmolLM, punctuation-absorbing space), todo fragment (SCOWL pin, why no plugin).**
- [ ] **Step 5: verify + commit.**

### Task 4: Model roles slice (branch `feat/pi-omp-parity-roles`)

**Prototype sources:** `/tmp/pi-lab/routing/model-roles/{model-roles.ts,role-core.ts,role-core.test.ts,work-defaults.json}`, `routing-report.md`; the repo's `dotfiles/pi/extensions/routing.ts`, `modules/home-manager/pi-routing.nix`, `tests/pi/{roles,required-integrations,routing,primary-routing}.mjs`, `tests/pi/routing-configuration.py`.
**Interfaces:** produces `local.pi.modelRoles` (contract) and consumes it in `pi-routing.nix`. Entry calls `createModelRoles(pi, options)` (options = rendered defaults: `modelRoles`, `retry {modelFallback, cooldownMs, fallbackChains}`, `cycleOrder`, `autoTitle`, `compactionRole`, `planMode`, `task.agentModelOverrides`, `agents`); keep flags `--smol --slow --plan --roles-config`, env `PI_<ROLE>_MODEL`, virtual provider `roles` model `auto`, commands `/models /role /use-role /plan /slow /build /commit /advisor /memory /widget /role-agents`, shortcut `ctrl+shift+u`, writable overlay `<agent-dir>/model-roles.user.json`.
Defaults mirror the user's omp work profile with pi's existing default: `default llm-platform/gpt-6.1-sol:high`, `plan llm-platform/claude-sonnet-5-5:xhigh`, `slow` same, `smol llm-platform/gpt-6-luna:low`, `commit`/`memory`/`widget` luna:low, `tiny luna:off`, `task sol:high`, `advisor sonnet:xhigh`, `vision null`; `taskAgents`: `build "@default"`, `plan "@plan"`, `scout llm-platform/gpt-6.1-sol:low`, `explore llm-platform/gpt-6-luna:low`, `title "@tiny"`. Settings: `defaultProvider = "roles"`, `defaultModel = "auto"` (`lib.mkForce`, overriding `pi-work.nix`), `defaultThinkingLevel` unchanged.

- [ ] **Step 1: behavior changes to the prototype** (tests first): `direct` requests (compaction etc.) stay on the previous physical model unless `compactionRole` is set; `/plan` does not restrict tools unless `planMode.readOnly` (then the allowlist is configurable and includes `question` and the ast/fetch read tools); only chat consumers are exposed in `/models`; `fallbackChains` empty and `modelFallback` false by default; overlay writes validated (invalid overlay → ignored with one warning, defaults kept); auth errors never fall back.
- [ ] **Step 2: unit tests** `tests/pi/role-core.test.mjs` (port the 16; add the changed behaviors) and `tests/pi/model-roles.test.mjs` (command wiring with a fake `pi`).
- [ ] **Step 3: module + cutover.** `pi-model-roles.nix` renders defaults JSON; resolve `taskAgents` selectors at eval time in `pi-routing.nix` role files; delete primary `routing.ts` and `primary-routing.mjs`; adapt `roles.mjs`, `required-integrations.mjs`, `routing.mjs`, `routing-configuration.py` and the fixtures in `checks/pi.nix` only if unavoidable (coordinate through the coordinator).
- [ ] **Step 4: PTY/request-log check** (`tests/pi/model-roles-pty.py`, 3 fake models): user turn → default; `--smol X` flag and `/models` edit persist to the overlay; scripted 429 with a configured fallback → fallback then restore after cooldown; image message → vision (or visible error); `/models` screen renders at 120 and 80 columns; `/plan` then `/build` switches models.
- [ ] **Step 5: docs** (`docs/pi-model-roles.md`: role table, selector grammar, what differs from omp: no advisor watchdog, memory engine, judge/auto-thinking, path-scoped models, Retry-After parsing; physical `/model` bypasses the router), todo fragment.
- [ ] **Step 6: verify + commit.**

### Task 5: Integration (coordinator)

- [ ] Merge slice branches; fold fragments into `TODO.md`, doc links into `docs/pi.md`; enable `local.pi.ui/lsp/ghostText/modelRoles` in `users/adriel-cachyos/default.nix` replacing `capabilities.editor` and `routing.agents`; write `docs/pi-gap-analysis.md`.
- [ ] Combined PTY check (`checks/pi-omp-parity.nix`): real generated agent dir with ui + lsp + ghost + roles + ast + web; assert statuses visible at 80 columns, ghost suffix inside the omp-theme editor, `/models` opens, no extension errors, `/reload` twice.

### Task 6: Verification

- [ ] `nix eval` both targets (`homeConfigurations.cachyos-framework13` and `nixosConfigurations.razer14` for regressions), `nix build` all `pi-*` checks and `configuration-contract`, lab screenshots of the final stack versus the omp reference, `ce-compound` lightweight note, final `git log` review. No switch.

## Self-Review Notes

- Spec coverage: D1-D3 → Task 1; D5 → Task 2; D6 → Task 3; D7 → Task 4; D8 split across Tasks 1, 4, 5; D9 in Task 4; gap analysis → Task 5.
- Residual risk list to repeat in docs: private-adapter coupling (D1), prototype patching (D3), persist command replaces `settings.json` symlink, overlay files without multi-process merge, `task` role edits need regeneration.
