# OpenCode vs Pi: essential feature complexity

Method: `wc -l` over the repo, so figures are estimates and the per-feature split is approximate. Nothing was built or run for this analysis. Pi counts are wiring only (nix, ts, py, packages, patches), not tests or docs. The OpenCode column is repo LOC for the same capability. "Built in" facts for OpenCode come from the OpenCode docs read for `docs/pi-gap-analysis.md`, not from running it.

## Totals

| | Earlier run | Latest run |
|---|---|---|
| OpenCode wiring | ~550 | ~550 |
| Pi wiring | ~5,000 | ~7,950 |
| Pi tests and checks | ~7,500 | ~10,150 |
| Pi docs | 1,243 | 1,421 |

Pi extensions grew from about 2,560 to 4,808 lines. Most of the growth is not essential.

## Essential features

| Capability | OpenCode (repo LOC) | Pi (repo LOC) | Pi vs OpenCode |
|---|---|---|---|
| LSP | 0 | ~550 | +550 |
| Format-on-write | 0 | ~480 | +480 |
| DAP | n/a (none) | ~235 | New capability |
| Todo | 0 | ~295 | +295 |
| Subagents, routing, jobs | ~52 (per-agent model and scout) | ~700 | +650 |
| Checkpoint, undo, redo | 0 | ~620 | +620 |
| Edit format, ast-grep | 0 | ~250 | +250 |
| Provider, Headroom, web, settings glue | ~500 | ~1,000 | +500 |
| Sandboxing | 0 | 0 | Missing in both |
| **Essential total** | **~550** | **~4,100** | **~7.5x** |

## Per-feature detail

### LSP

**Built into OpenCode (0 repo LOC):**
- About 35 language servers that it knows how to find.
- Diagnostics are fed back to the model after edits.
- An experimental `lsp` tool for navigation.
- You turn it on with a config flag.

**Added by hand in Pi (~550 LOC):**
- Pi has no LSP at all. We pinned the third-party `@ian-pascoe/pi-lsp` with its 15-package npm lockfile (`packages/pi-lsp*`, ~228 LOC).
- Two patches fix bugs in that extension:
  - It skipped post-edit diagnostics for push-only servers such as typescript-language-server.
  - It waited the full 15 s on clean edits.
- Servers come from nixpkgs, each with its own wrapper PATH and settings: gopls, typescript, nixd, basedpyright, ruff, pyrefly and bash. This is `modules/home-manager/pi/lsp.nix`, 292 LOC.
- `dotfiles/pi/extensions/lsp-status.ts` (32 LOC) bridges the extension's status into the footer.
- There are about 60 lines of checks beyond this.

OpenCode runs the same servers without any of this wiring. Our extra work is mostly Nix pinning and fixing a third-party extension.

### Format-on-write

**Built into OpenCode (0 repo LOC):** about 25 formatters that run automatically after edits, enabled by config.

**Added by hand in Pi (~480 LOC):**
- Pi has no formatting. We wrote `format-core.ts` and `format-on-write.ts` (278 LOC).
- `modules/home-manager/pi/format.nix` (204 LOC) selects the formatters from nixpkgs: gofumpt, jq, nixfmt, ruff, stylua, shfmt, rustfmt, zig, OpenTofu and Biome.
- It depends on Pi running `tool_result` handlers in extension load order. A check fails first if that ever changes.
- Zig and rustfmt add about 3.5 GiB of closure.

### DAP

- **OpenCode:** has no debugger, so there is nothing to compare against.
- **Pi:** the pinned `pi-dap` extension plus adapters from Nix (delve, debugpy, js-debug, gdb, Dart) is ~235 LOC. Wiring those adapters is the only cost.

### Todo

- **OpenCode:** built in, 0 LOC.
- **Pi:** `todo-core.ts`, `todo.ts` and `pi/todo.nix` (~295 LOC) give task ids, one task in progress, blocked reasons and a checklist above the prompt.

### Subagents, routing and jobs

- **OpenCode:** primary agents and subagents are built in. Per-agent models take a short Nix option and the `scout` agent adds a few lines, ~52 LOC.
- **Pi:** `pi-subagents` is pinned and patched for required MCP. We added `routing.nix` (249 LOC), `jobs.nix` and `job*.ts` (~440 LOC) for background jobs, plus worktree isolation.

### Checkpoint, undo and redo

- **OpenCode:** undo and redo are built in, 0 LOC.
- **Pi:** `checkpoint-core.ts`, `checkpoint.ts` and `checkpoints.nix` (~620 LOC) snapshot the working tree before every prompt and provide `/undo`, `/redo` and `/checkpoints`.

### Sandboxing

- **OpenCode:** none. It runs with `permissions: autoaccept` and has allow/ask/deny rules.
- **Pi:** none. `dotfiles/pi/planning-instructions.md` says outright that tools are not sandboxed.
- Neither tool contains anything. Checkpoints only limit the damage of a bad edit.

## Non-essential code with no OpenCode equivalent

Total: ~3,350 LOC, about 42% of Pi wiring.

| Item | Pi LOC | OpenCode |
|---|---|---|
| OpenCode-style UI skin (`opencode-ui*.ts`) | ~1,360 | Native, 0 |
| Ghost-text completion | ~750 | None |
| Model roles | ~570 | Per-agent model option, 0 extra |
| Eval kernel | ~455 | None |
| omp theme layer and patches | ~150 | n/a |

## Carrying cost

- **Fragility:** `opencode-ui`, `neutral-foreground` and `pi-omp-theme` all decorate Pi internals. Two overlapping skin layers (omp and OpenCode) now ship together.
- **Tests:** tests and checks (~10,150 lines) are larger than the ~7,950 lines of wiring they cover.
- **Pins and patches:** the pinned or patched third-party packages are about 540 lines of nix, up from 347. `TODO.md` has 86 bullet lines.

## Conclusions

1. Essential parity is about 4,100 lines of wiring against OpenCode's ~550, roughly 7.5x. Much of the growth since the first run is code you chose to add (checkpoints, jobs, rtk), not recreation of OpenCode's essentials.
2. Non-essential code is about 42% of Pi wiring. The UI work is most of the growth.
3. Sandboxing is missing from both tools and is a separate item.
4. Cut candidates: the omp theme layer (overlaps `opencode-ui`), ghost text and eval would remove about 1,400 lines and several fragile patches. Model roles is next if `/models` goes unused.
