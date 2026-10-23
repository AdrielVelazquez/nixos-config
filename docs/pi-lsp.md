# Pi language servers

`local.pi.lsp.enable = true` installs the pinned `@ian-pascoe/pi-lsp@0.15.1`
extension through Nix. It does not run `pi install`, npm lifecycle scripts, a
server installer, or a cloud service. Server startup is lazy, after a matching
file operation or an explicit LSP query.

Successful native `edit` and `write` results contain current LSP diagnostics
**before the next model request**. A repaired file reports
`LSP diagnostics: no diagnostics`; a server failure or diagnostic deadline is
not reported as clean. Existing upstream version tracking rejects superseded
push diagnostics. This is diagnostic feedback, not automatic formatting.

## Servers and defaults

All servers below default to enabled. Commands are absolute Nix store paths;
`runtimeInputs` adds trusted package binaries ahead of the inherited PATH.
Root markers select a project root, but `requireRootMarker = false` permits
standalone files. Settings and root markers mirror `dotfiles/nvim/lsp/*.lua`
where there is an existing Neovim configuration.

| Server key | Languages | Runtime policy |
|---|---|---|
| `gopls` | Go, go.mod, go.sum | Go 1.26 on its private wrapper PATH; staticcheck, gofumpt, analyses/hints/semanticTokens match Neovim. `GOTOOLCHAIN=local`, `GOTELEMETRY=off`, `GOPROXY=off`, `GOSUMDB=off`. |
| `typescript` | TS/JS, TSX/JSX, module variants | typescript-language-server with **typescript_5 5.9.3** `tsserver.js`; TypeScript 7 is not compatible. Automatic typing acquisition is disabled. |
| `nixd` | Nix | Same `flake.nix`/`.git` roots as Neovim. |
| `basedpyright` | Python | autoSearchPaths, useLibraryCodeForTypes, openFilesOnly match Neovim. |
| `ruff` | Python | `ruff server`, Neovim roots, no extra settings. |
| `pyrefly` | Python | `pyrefly lsp`, Neovim roots, no extra settings. |
| `bash` | Bash/shell | bash-language-server with ShellCheck on its private wrapper PATH. |
| `rust` | Rust | rust-analyzer; uses the project's cargo from inherited PATH, not a bundled toolchain; `CARGO_NET_OFFLINE=true`. |
| `lua` | Lua | lua-language-server and Neovim `.luarc.json`/`.luarc.jsonc` roots. |
| `marksman` | Markdown/MDX | `marksman server`, Neovim roots. |
| `json` | JSON/JSONC | vscode-json-languageserver `--stdio`, validation explicitly enabled; only local `file:` schemas are handled directly. Remote schema requests are delegated to Pi, which does not implement schema fetching. |
| `terraform` | Terraform/HCL | terraform-lsp (the user's Neovim server, **not** terraform-ls). |
| `zls` | Zig/ZON | zls; project Zig is supplied by the user's development environment. |

Multiple Python servers are intentional, matching Neovim; they may report
overlapping findings. No Rust/Zig toolchain is added to the user's global PATH.
Missing project tools/dependencies produce visible failures or incomplete
analysis, not downloads or a substitute compiler invocation.

Missing executable failures identify the server and report `process failed to
start`, with upstream's private stderr-log path. That log may be empty when no
process could start; the model-facing error does not include the original ENOENT.

## Configuration

```nix
local.pi.lsp = {
  enable = true;
  servers.ruff.enable = false;
  servers.gopls.settings.gopls.staticcheck = true;
  timeouts.diagnosticsMs = 15000;
  status.enable = true;
};
```

Each `servers.<name>` accepts `enable`, `package` (nullable), `command`, `args`,
`languages = [{ extensions = [ ".ext" ]; languageId = "id"; }]`, `rootMarkers`,
`requireRootMarker`, `initializationOptions`, `settings`, `environment`, and
`runtimeInputs`. With a package, a relative command names a binary in its
`bin/`; without a package, command must be absolute. Empty enabled commands
fail evaluation. A nonexistent absolute executable fails visibly at runtime.
Set environment entries to `null` to remove inherited variables from that
server process (for example provider credentials).

The generated settings set `includeHintDiagnostics = false` and default
initialize/request/workspace/diagnostic/shutdown deadlines of
45s/10s/15s/**15s**/5s. The diagnostic window intentionally exceeds the tested
nine-second delayed-publish case. Server-specific settings and `timeouts` are
merged declaratively; disabling one server removes its generated definition.
`local.pi.lsp.entries.lsp` exposes the generated extension entry.

Global managed servers work with `--no-approve`; an **untrusted** project's
`.pi/settings.json` cannot add or override a server. Once Pi trusts a project,
its executable LSP configuration is upstream's trusted-project policy, not a
sandbox. Do not trust unknown project settings. Language servers inherit the
user's environment unless removed through `environment`; they are not secret
isolation boundaries.

## Tools and status

Tools include diagnostics, hover, goto-definition, references, document/workspace
symbols, rename, code actions and explicit workspace-edit application. Rename
returns a preview; applying edits is a separate operation. Upstream does not
execute command-only code actions. Workspace edits can affect paths outside
Pi's current directory; inspect previews before applying them.

The bridge contributes `LSP gopls ● · typescript ●` through
`ctx.ui.setStatus("lsp", ...)`; idle sessions show `LSP N configured`. It never
replaces the footer/editor. `/lsp` remains upstream's server management menu.
Status refreshes at session start, after tools and at agent end, and clears at
shutdown. An idle server crash can retain its badge until the next event.
Headless modes use the same diagnostic path without requiring a TUI.

Managed `settings.json` remains a read-only symlink during ordinary sessions.
The upstream `/lsp` enablement commands can persist settings: prefer Nix
configuration for permanent changes rather than editing managed files.

## Patch and verification

`packages/pi-lsp-path-push-diagnostics.patch` removes two pull-capability gates
that otherwise exclude real push-only gopls and TypeScript diagnostics after
mutations. It reuses upstream's existing fresh/version-aware collector; it does
not implement a second transport, retry policy, compiler fallback, or fixed
sleep. The separate Nix adapter applies it during the immutable package build.
Remove the patch only after an upstream release passes the same checks without
it. [Upstream source](https://github.com/ian-pascoe/pi-extensions/tree/main/packages/pi-lsp)
and [issue submission](https://github.com/ian-pascoe/pi-extensions/issues/new?title=pi-lsp%3A%20post-edit%20diagnostics%20skip%20push-only%20servers)
are the tracking points; no upstream issue has been filed by this change.

Run from the repository:

```sh
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix build --no-link .#checks.x86_64-linux.pi-lsp
```

The self-contained check runs bridge/package unit tests and real Pi against a
scripted loopback-only provider with real Go and TypeScript servers. It inspects
the **immediately following model request** for errors and explicit clean
repairs, exercises real navigation and rename preview, delays real gopls
notifications nine seconds, rejects untrusted-project server injection, tests a
missing binary, preserves managed settings symlinks, and captures a real footer
PTY screenshot. Its output includes request/event evidence and `lsp-status.png`.
Other server definitions/binaries are checked, but real-project behavior for
those languages is not claimed by the Go/TS acceptance fixture.
