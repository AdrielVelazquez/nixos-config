# Pi omp/opencode parity: design

Date 2026-10-23. Branch `feat/pi-omp-parity` (worktree `.worktrees/pi-omp-parity`).
Target config: `homeConfigurations.cachyos-framework13` (user `adriel-cachyos`). Validation host: this CachyOS machine
(standalone Home Manager). The user tests the finished branch himself; nothing here runs `home-manager switch`.

## Intent

The Nix-managed upstream Pi 1.3.0 looks and behaves worse than the omp and OpenCode the user runs next to it. A first
attempt (`pi-zentui` + local `visuals.ts` + hard-coded `managed-opencode` theme) failed visually. The user wants Pi to
imitate omp (primary) and OpenCode through plugins, themes and thin extensions, and asked for four concrete things:

1. Visual parity (omp status row, tool cards, prompt box, code colors).
2. Working LSP: diagnostics after every edit/write fed back to the model, navigation tools, server status in the UI,
   richer code coloring in the transcript.
3. omp's inline ghost-text *word* completion.
4. omp's role-based model routing with a `/models` role screen (roles, retry fallbacks, `--smol/--slow/--plan`).
Plus a written gap analysis of default Pi versus omp and OpenCode (`docs/pi-gap-analysis.md`).

## Evidence

Five independent evaluators ran real pi 1.3.0 in a PTY on the user's actual terminal (Ghostty "Mona Lisa" palette on
`#000000`, Maple Mono NF) against a scripted local model. Reports, pins and screenshots are archived in
`docs/reviews/2026-10-23-pi-omp-parity-evaluation/` (labels: [E] executed, [C] read in code, [H] hypothesis).
Root cause of the "drab" look [E]: Pi prints assistant prose, editor text and unclassified code tokens in the
terminal's default foreground (here `#f7d66a`), and no theme token reaches it.

## Decisions

| # | Decision | Basis |
|---|---|---|
| D1 | Visual owner: `@nguyenquangthai/pi-omp-theme@1.0.26`, preset `omp`, owns header/footer/editor/tool cards. | User choice. Closest to omp [E]. |
| D2 | Themes shipped: `omp-reference` (default, sampled from the user's omp screenshot) and `omp-dark` (stock omp dark port), both truecolor; `pi-terminal-theme@0.2.0` JSON-only as optional palette-following alternates. | Theme report. |
| D3 | `neutral-foreground.ts` (45 lines) wraps `Markdown.prototype.render` and `CustomEditor.prototype.render` to reopen `theme.text`. Version-coupled to pi 1.3.0, restored on shutdown. | No documented hook exists [C]. |
| D4 | No Shiki/TextMate highlighter now. | User choice. Documented as a possible later step. |
| D5 | LSP: `@ian-pascoe/pi-lsp@0.15.1` + 15-line push-diagnostics patch (named `pi-lsp-path-push-diagnostics`) + status bridge that only calls `setStatus("lsp", ...)`. Servers come from nixpkgs: Go, TypeScript/JS, Nix, Python, Bash, Rust plus every server the user's Neovim uses (gopls, basedpyright, ruff, pyrefly, lua-language-server, marksman, nixd, terraform-lsp, vscode-json-languageserver, zls). | User choice; LSP report. |
| D6 | Ghost text: own extension (no plugin qualifies [C]/[E]); n-gram+unigram over a SCOWL word list from nixpkgs, learns from the transcript and accept/reject feedback, mounted in `resources_discover`, wraps the current editor factory. | Ghost report. |
| D7 | Roles: own dependency-free router on `pi.registerVirtualModel` (`roles/auto`), real consumers only (default, smol, slow, plan, commit, task, tiny, vision, advisor, memory, widget + custom roles), fallbacks supported but empty and off by default, Nix defaults immutable plus a writable overlay JSON in the agent dir. | User choice; routing report. |
| D8 | Clean cutover: remove `pi-zentui`, `visuals.ts`, `managed-opencode`, `zentui.json`, primary `routing.ts`, `local.pi.capabilities.editor`, `local.pi.routing.agents`. | Repo contract: no shims. |
| D9 | Pi's own default role stays `llm-platform/gpt-6.1-sol:high` (not omp's Sonnet default); compaction stays on the active model unless `compactionRole` is set; `/plan` stays a soft mode (model + prompt) unless `planMode.readOnly = true`. | Preserves documented pi behavior (docs/pi.md). |

## Goals, non-goals, anti-goals

- Goals: everything in "Intent" working end to end, immutable and pinned, verified by real-pi checks.
- Non-goals: omp's background advisor watchdog, memory consolidation engine, DAP debugger, collab, Hashline edit mode,
  SmolLM word model, path-scoped `enabledModels`, round-robin credentials, usage-aware fallback.
- Anti-goals: no `pi install`, no npm lifecycle scripts, no runtime downloads (servers, grammars, models), no telemetry,
  no cloud calls, no stub roles or no-op settings, no change to the Headroom/Tuios/Reddit-provider contracts.

## Constraints

- Nix owns every plugin: fixed-output fetch (sha512 computed by `nix store prefetch-file` and compared with the registry
  `dist.integrity`), vendored lock via `importNpmLock` where a package has dependencies, `--ignore-scripts`.
- New flake-visible files must be `git add`ed before `nix eval`.
- Every pin/exception gets a TODO.md entry (reason, upstream link, obsolescence check, target config).
- The agent directory is Home Manager read-only; writable runtime state lives in separate overlay files.

## Left to the builder

Option and file names beyond the contracts in the plan, exact CSS-like details of status layout, and test fixtures.
Known residual risks to carry into docs: pi-omp-theme's guarded private adapters; `neutral-foreground` method wrapping;
`pi-omp-theme` persist command replaces the managed `settings.json` symlink; ghost-text/roles overlay files lack
multi-process merge; roles `task` edits need frontmatter regeneration.
