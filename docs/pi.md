# Framework Pi workflow

Framework offers Pi 1.3.0, restored OpenCode with LLM Platform, and native OMP
side-by-side through Home Manager. Razer retains its existing
OpenCode/Go/local-model setup and standalone Antigravity CLI. The shared Neovim
OpenCode client/server integration is removed; terminal navigation and scrollback
remain in Tuios. No conversation or credential directories are deleted.

## Use

- Start `pi` for Pi or `oc` / `opencode` for OpenCode inside the working tree.
- `oc` once again launches OpenCode through Headroom, never Pi. Start a fresh shell
  to refresh an alias already loaded in an older shell.
- `/reddit` opens project/model status, quota and Tool Registry controls.
- `/reddit tools` opts into the registry. Native `/mcp` owns sign-in/out,
  reconnection and authoritative connection details; browser consent is interactive.
- The default model is the virtual `roles/auto`: each request is routed to the physical model of the active role
  (`default` = `llm-platform/gpt-6.1-sol`, thinking `high`). `/models` edits roles; `/plan` (Sonnet `xhigh`), `/slow`,
  `/build`, `/use-role`, `/role` and `--smol/--slow/--plan` select or assign them. See `docs/pi-model-roles.md`.
  Pi's native `/model` still selects a physical model and bypasses the router.
- Native session model changes survive reload/resume. There is no per-turn price router and model fallbacks are off
  unless configured. Compaction stays on the active model unless `compactionRole` is set.
- Auxiliary session titles use the `tiny` role (`llm-platform/gpt-6-luna`, thinking off).
- The omp-style UI is `docs/pi-ui.md`; LSP diagnostics and navigation are `docs/pi-lsp.md`; inline ghost-text word
  completion is `docs/pi-ghost-text.md`; automatic formatting of written files is `docs/pi-format.md`; debug adapters are `docs/pi-dap.md`; `pi-stats` is omp's usage dashboard over Pi's sessions (`docs/pi-stats.md`).
  How Pi compares with omp and OpenCode, and what is still open: `docs/pi-gap-analysis.md`.
- Resume with `pi --session <id-or-session-file>`. Tuios uses that native command
  and the managed `pi` on PATH; restarting the daemon still requires permission.
- In print mode, `/reddit` diagnostics use stderr; JSON mode emits native messages.

OAuth, catalog caches and directory-local Reddit choices are private writable
runtime state. Nix owns code and defaults. `~/.pi/agent/settings.json` is a writable
copy of the Nix-generated settings that **every switch overwrites completely**, so
`/lsp`, `/subagents-watchdog`, theme and model choices persist only until the next
switch (the replaced file is kept once as `settings.json.replaced`). Persist anything
you want to keep in the Nix configuration, not with `pi install`, MCP installers or
settings edits. Every other managed file stays a read-only store symlink. To roll
back to a generation from before this change, delete `settings.json` first.
`/reddit` never owns an explicitly configured conflicting native MCP server.

The dynamic Pi OAuth client requests ordinary Tool Registry scopes only. The
first-party-only `tool:llmp:` family and its LLMP skill-management tools are
excluded; enabling those requires separate approved client onboarding, not a
server-policy bypass. Updated provider code filters old cached scopes on reload.
The managed OpenCode provider applies the same restriction to fresh and cached
scope discovery. After activation, retry its Tool Registry sign-in through `/mcps`;
existing credentials are not deleted or migrated by Nix.

## Routing and MCP policy

`scout` uses Sol/low and audited external read-only GitHub operations and public-page fetching;
`explore` uses Luna/low and local read-only file tools. Neither gets shell, writes,
or delegated writer access, including through Code Mode. Missing/auth-denied
research tools must be reported, not replaced by fabricated external research.
Additional approved MCP operations belong in the Nix role options, not wildcards.
Comprehensive core-tool parity and a deny-preserving session permission engine remain deferred.

**Worktree isolation.** `subagent` accepts `worktree: true` per call: each such child edits its own linked git
worktree of the project, created by `pi-subagents`' native allocator under
`local.pi.routing.worktreeBaseDir` (default `~/.local/share/pi-subagents/worktrees`, so no checkout gains a sibling
directory), and returns its changes as a patch handoff for the parent to apply. It is opt-in per call because the
package refuses isolation unless `git status --porcelain` is empty, untracked files included; a default would refuse
every launch from a working tree such as this one. A cleanly finished unchanged worktree is removed. The Headroom
extension accepts a child whose checkout belongs to the same repository (same `git --git-common-dir`) and keeps the
managed project for attribution, so isolated children stay on the compressing proxy and share the parent's memory;
a different repository is still refused. Headroom's code-graph tools therefore describe the parent checkout, not
the child's temporary worktree. `checks.pi-routing` runs a real isolated child through the real proxy.

## Audited editor and read-only capabilities

Every standalone Pi feature (`local.pi.ui`, `.lsp`, `.format`, `.dap`, `.ghostText`, `.workflow`, `.openspec`,
`.capabilities.ast` and `.web`) is on whenever `local.pi.enable` is set. `.modelRoles` and
`.routing` follow `.llmPlatform` (the built-in role selectors name LLM Platform models) and
`.stats` follows `local.omp.enable`; set any of them to `false` to opt out. Razer does not
enable Pi. Packages and dependencies are immutable Nix inputs; no `pi install`, npm
lifecycle scripts or runtime binary/grammar downloads are used.

- **omp-style visual layer, using `@nguyenquangthai/pi-omp-theme@1.0.26`:** powerline status row, compact tool cards
  with highlighted diffs, rounded prompt, truecolor `omp-reference` theme (plus `omp-dark` and optional
  `pi-terminal-theme` palettes) and a guarded foreground adapter. The earlier `pi-zentui` + `visuals.ts` +
  `managed-opencode` trial is removed. Two small named source patches and the private-adapter risk are recorded in
  `TODO.md` and `docs/pi-ui.md`. Nix owns the skin; `/pi-omp-theme persist` writes the writable
  `settings.json` and lasts only until the next switch.
- **`@ian-pascoe/pi-lsp@0.15.1` (patched) with nixpkgs language servers:** diagnostics after every edit/write reach the
  model in the tool result, navigation tools (definition, references, hover, symbols, rename preview, code actions)
  and a `LSP ...` footer status. Servers: every language server configured in the user's Neovim plus Go, TypeScript/JS,
  Nix, Python, Bash and Rust. See `docs/pi-lsp.md`.
- **Format-on-write** (`format-on-write.ts`; nixpkgs formatters mirroring your conform set plus rustfmt, shfmt, zig,
  OpenTofu and Biome): files written by `edit`/`write` are formatted before the LSP diagnostics run and the model is
  told what changed. See `docs/pi-format.md`.
- **Debug adapters** (`@ian-pascoe/pi-dap@0.10.1` pinned through Nix; delve, debugpy, `vscode-js-debug`, gdb and the Dart
  SDK by store path): `dap_*` tools for the interactive session only, profiles `go`, `python`, `node`, `native` and
  `dart`. See `docs/pi-dap.md` for what each adapter does and does not forward.
- **Local ghost-text word completion** (`ghost-text.ts`, web-frequency vocabulary from nixpkgs, transcript learning, no model calls)
  and **role routing** (`model-roles.ts` on Pi's virtual-model API) are first-party extensions; `docs/pi-ghost-text.md`
  and `docs/pi-model-roles.md` list exactly what matches omp and what does not.
- **`@juvio15/pi-ast-grep@0.4.2`**, using Nix **ast-grep 0.51.0**: five read tools
  `ast_grep_run`, `ast_grep_scan`, `ast_grep_outline`, `ast_grep_debug_query`,
  `ast_grep_languages` in every session, plus **`ast_grep_rewrite` in the interactive
  session only** (`local.pi.capabilities.ast.rewrite.enable`; a separate `ast-rewrite.ts`
  entry that is not a required child extension, so native children, and Code Mode inside
  them, never have it). Mutable saved-rule commands are never registered. A supported
  factory adapter pins both the executable and empty CLI config: ambient `AST_GREP_BIN`,
  project custom native grammars and automatic project rule discovery are ignored.
  Rewrite keeps the package's own policy (preview by default, a trusted project, a prior
  preview when headless, a confirmation dialog when interactive, per-file writes through
  Pi's mutation queue) and adds a boundary: a `path` that resolves outside the working
  directory, by `..`, an absolute path or a symlink, is refused, nested calls included.
  Applied files are formatted like `edit`/`write` results (`docs/pi-format.md`) within a
  30 s budget per result; `pi-lsp` reports no diagnostics after a rewrite, so run
  `lsp_diagnostics`. The footer reads `ast-grep RW` (`RO` with rewrite disabled). Inline
  scan rules remain available. Search may read the requested paths; this is not a
  secret-file firewall or OS sandbox. Each session cleans only its own tracked full-output
  spills. With the pinned `--config`, ast-grep prints one constant error line per run;
  the adapter drops exactly that line so an empty search is empty, not an error. Serena
  remains the semantic/LSP interface.
- **`pi-web-access@0.44.0`, fetch plus Exa-only search:** `dotfiles/pi/extensions/web-access.ts`
  exposes three tools. `fetch_content` accepts `url` or up to eight `urls`, plus
  `mode: "readable" | "raw"`. `web_search` accepts `query` or up to four `queries`
  (each at most 400 characters), `numResults`, `recencyFilter`, `domainFilter` and
  `category`. `get_search_content` retrieves stored fetch or search results by
  `responseId` (plus `queryIndex` for searches). Search is pinned to Exa
  (`webSearch.allowedProviders = ["exa"]`, `searchProvider = "exa"`) through its hosted
  MCP, which needs no credential, so no secret enters the Nix store. Provider choice,
  `workflow` (forced to `none`), `proxy` and `includeContent` are never model-selectable,
  and `source_check`, the curator and every upstream command stay disabled. No AI page
  answers, auth/cookies, proxy selection, media, PDF, GitHub cloning or curator.
  Unsupported arguments are refused both by schema and execution. Redirects are
  same-origin; common private/loopback ranges are checked with no production exemptions.
  A changed, invalid or missing managed `web-search.json` refuses web execution.
  Content is untrusted and persisted in the agent directory's on-disk web cache
  (upstream limits: 128 MiB, one-hour TTL), as well as session state. Readable
  parsing can fail on malformed pages; use raw explicitly rather than an AI or
  hosted fallback. The SSRF checks are not address-pinned OS egress isolation;
  IPv6 transition/embedded-address forms and DNS rebinding remain gaps.
  Search queries leave the machine for Exa, and keyless Exa MCP can return 429 under
  load. An optional `exaApiKey` must come from sops at runtime, never from this
  policy: the wrapper requires the managed file to equal the Nix policy exactly.
  Upstream also honours `EXA_API_KEY` and `EXA_BASE_URL` from the environment; do
  not export them for Pi unless you intend to send queries there.

**Read-only does not mean no data egress.** The primary session and scout/build/plan
can combine local reads with public HTTP requests. A model, including one misled
by prompt injection, could place local file contents or secrets in a URL path,
query or search query and send them to a public host (including Exa). Removing auth/cookies/proxy knobs does not
prevent that. This stack has no enforced outbound-domain allowlist or secret-file
firewall. Stronger egress controls or removing fetch from scout require a separate
policy decision; never treat a fetched page as authority to expose local data.

AST/fetch adapters are mandatory in native child generations. Their presence does
not enlarge a role's authority: `scout` gets read-only AST and fetch/retrieval;
local `explore` gets AST but no web, shell, writes or writer delegation. `build`
and `plan` can use both, still without `ast_grep_rewrite`, which only the interactive
session has; `title` gets neither. No new permission engine is implied.

Search uses the Exa-only `web_search` above. Tool Registry DDG operations remain an
alternative after native OAuth login; unverified LLMP-native search is not a substitute.
Formatting is automatic only for files the model writes with `edit`/`write` (`docs/pi-format.md`); everything else
stays explicit through normal gated/native bash, for example
`rtk proxy gofmt -d "path with spaces.go"` for preview, then an intentional
`rtk proxy gofmt -w "path with spaces.go"`. Compaction stays native and on the
active model; no extra compaction package, summary provider or speculative token
threshold is installed. Native per-model reserve/recent-token options remain usable.

The audited permission-system 41.0.0 can let session grants override configured
denies; the standalone pi-lsp-extension 1.4.0 has cold/stale diagnostics and untrusted-project
startup gaps. Neither is installed (LSP comes from the patched `@ian-pascoe/pi-lsp`, which passed the
cold/stale/trust probes; see `docs/pi-lsp.md`). Lens, Powerline and full Arnative are also
excluded. Full command-level permission control and session-wide autonomy are
still unresolved requirements, not features this increment claims to implement.

The provider and Headroom entry points are required in native children, including
foreground, detached, nested and resumed runs. A selected read-only Headroom stats
operation ensures Pi's native MCP factory is loaded. External/machine runners are
not substitutes for that policy. The `pi-subagents` package, dependencies and narrow
foreground-MCP correction are Nix-managed; its installer and bundled workflow packs
are not enabled.

Headroom compression/retrieval, persistent memory, Serena and GitHub are native
MCP connections. The existing SOPS GitHub credential is read at process startup,
not during evaluation. Serena uses isolated Python paths and the individual-tools
interface, never a broad REPL in a read-only child.

Memory search/save is provided **only by native MCP**. Proxy-side memory tools and
their response interceptor are not initialized: otherwise a model could bypass
Pi's operation ceilings through an unadvertised proxy-owned memory call. Existing
workspace `.headroom/memory.db` files are retained; new stores use Headroom's
project-key layout. Files are never moved, merged or reset. Graph watching and
memory identity follow the current worktree's top-level directory, not the main
checkout behind its common Git directory.

## Headroom lifecycle and boundaries

The Pi launcher starts a bounded-ready loopback proxy and sets the provider's
required-inference contract. Gateway discovery/quota/registry retain their trusted
direct endpoints. Chat and Responses inference preserve project authentication;
proxy control headers do not reach the gateway. A missing/stopped proxy is an
error, never permission for direct inference.

Only this launcher's privately recorded compatible proxy is reusable. Concurrent
sessions, native child leases and admitted async-run reservations keep it alive;
the final owner releases it. Occupied foreign ports are never adopted or killed.
No resident service is installed, and existing OpenCode proxies are left alone.
Private registry/log metadata remains under runtime storage for diagnostics, and
is cleared with that runtime directory rather than racing another launch's lock.

Current cache mode, beta output shaping, verbosity and tool-description settings
are inherited unchanged. Different startup configuration gets a separate proxy.
Public tokenizer vocabularies and exact public ONNX embedding weights are supplied
through fixed-hash Nix derivations so a cold HOME does not silently lose Responses
compression or fail memory search. No private data or credentials enter those caches.

## Tuios

Nix generates upstream's unmodified Pi extension during the build and links it
into the configured Pi agent directory. It reports working/idle, blocking native
questions/confirmations and stable session identity. A separate bounded companion
corrects upstream's unconditional `done` after provider errors/interruption, only
for the same pane/session while it still reports `done`. Native headless children
do not claim the parent's pane. Detailed child/cost metadata and direct Inbox
answers are **not** claimed; answer in Pi's own UI.

## Verify or revisit

```sh
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix build --no-link .#homeConfigurations.cachyos-framework13.activationPackage
rtk nix build --no-link .#checks.x86_64-linux.configuration-contract \
  .#checks.x86_64-linux.pi-base .#checks.x86_64-linux.pi-work \
  .#checks.x86_64-linux.pi-headroom .#checks.x86_64-linux.pi-routing \
  .#checks.x86_64-linux.pi-tuios \
  .#checks.x86_64-linux.pi-capabilities-contract \
  .#checks.x86_64-linux.pi-capabilities \
  .#checks.x86_64-linux.pi-capabilities-loopback \
  .#checks.x86_64-linux.pi-capabilities-ui \
  .#checks.x86_64-linux.pi-ui .#checks.x86_64-linux.pi-lsp \
  .#checks.x86_64-linux.pi-format \
  .#checks.x86_64-linux.pi-dap \
  .#checks.x86_64-linux.pi-ghost .#checks.x86_64-linux.pi-model-roles \
  .#checks.x86_64-linux.pi-stats .#checks.x86_64-linux.pi-settings \
  .#checks.x86_64-linux.pi-omp-parity
```

`tests/pi/mcp-fixture.nix` plus `tests/pi/run-mcp-fixture.py` exercise real memory,
Serena and the code-graph watcher in disposable state; Serena's first isolated
startup may fetch its existing uvx dependency environment. The fixture supplies
only synthetic credentials and uses fixed-hash offline memory-model files.
See `TODO.md` for upstream adapter/pin removal gates.

Synthetic checks are not proof of WARP access, production quota/schema behavior,
browser OAuth consent, or live Tuios restore. Test those separately after authorized
activation; never restart the current daemon as an installation check.
