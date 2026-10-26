# Pi Home Manager modules

`core.nix` owns the `pi` wrapper, the generated `settings.json`, `mcp.json`, `models.json` and `AGENTS.md`, and the
`local.pi` option surface. Every other file is one feature that adds extensions, tools or role files to it. User
documentation is in `docs/pi.md`; the exceptions and pins each feature carries are in `TODO.md`.

| File | What it adds | Interactive session | Native children |
|---|---|---|---|
| `core.nix` | wrapper, settings, MCP, API keys, discovery tools | yes | n/a |
| `ui.nix` | opencode skin, themes | yes | no |
| `capabilities.nix` | `ast_grep_*`, `ast_grep_rewrite`, web fetch and search | yes (rewrite only here) | read-only AST and web are required |
| `lsp.nix` | language servers, diagnostics after edits, `lsp_*` | yes | no |
| `format.nix` | format-on-write | yes | required (build, plan write files) |
| `dap.nix` | `dap_*` debug tools | yes | no |
| `hashline.nix` | hash-anchored read, edit, grep | yes | build and plan only |
| `eval.nix` | persistent Python `eval`, `codemode` | yes | no |
| `todo.nix` | `todo` task list | yes | no |
| `model-roles.nix` | `roles/auto`, `/models`, `/plan`, consumers | yes | n/a |
| `routing.nix` | subagent role files and required child extensions | n/a | defines them |
| `llm-platform.nix` | Reddit LLM Platform provider and Tool Registry | yes | required |
| `headroom.nix`, `headroom-providers.nix` | session-owned Headroom proxy, MCPs, provider routing | yes | required |
| `workflow.nix`, `openspec.nix` | Superpowers, CE skills, OpenSpec skills and prompts | yes | n/a |

## Conventions

- `lib.nix` is passed to every module as `piLib`. `piLib.mkEntry` and `piLib.mkReexport` write the entry module Pi
  loads for a first-party extension, `piLib.extensionPath` names an extension file, and `piLib.mkFeatureEnable` and
  `piLib.mkEntriesOption` are the shapes every feature repeats. Extensions are always referenced through the
  whole `dotfiles/pi/extensions` directory: a store path made from a single file drops the modules it imports.
- A feature contributes to `local.pi.extraSettings.extensions` (the interactive session), to
  `local.pi.requiredChildExtensions` (every native child) or to `local.pi.routing.writerExtensions` (the build and
  plan children). Interactive-only is the default; a child gets an extension only where a check says it must.
- Load order matters. `default.nix` keeps the import order, and `lib.mkOrder` places the extension that
  must sit before it: format-on-write (900) runs before LSP diagnostics. `checks.pi-format` and `checks.pi-capabilities-contract` fail first when the order drifts.
- `local.pi.<feature>.entries` is a read-only handle on a feature's entry modules for the checks.

## Adding a feature

1. Write the extension under `dotfiles/pi/extensions/`: a pure `*-core.ts` that a plain `node --test` can exercise
   and a thin `*.ts` that talks to Pi.
2. Add `<feature>.nix` here, import it in `default.nix`, and expose `enable` through `piLib.mkFeatureEnable`.
3. Register a check in `checks/` (see `checks/default.nix`) that runs the real Pi against a scripted provider.
4. Record any pin, patch or workaround in `TODO.md` with its removal condition.
