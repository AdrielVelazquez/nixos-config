# Framework Pi workflow

Framework selects Pi 1.3.0 as its primary workflow and keeps OpenCode with LLM
Platform available alongside it through Home Manager. Razer retains its existing
OpenCode/Go/local-model setup and standalone Antigravity CLI. The shared Neovim
OpenCode client/server integration is removed; terminal navigation and scrollback
remain in Tuios. No conversation or credential directories are deleted.

## Use

- Start `pi` (or the compatibility alias `oc`) inside the working tree.
- Start `opencode` explicitly for the alternate LLM Platform workflow; its new-session
  default is `llmplatform/gpt-6.1-sol`, with inference still routed through Headroom.
- `/reddit` opens project/model status, quota and Tool Registry controls.
- `/reddit tools` opts into the registry. Native `/mcp` owns sign-in/out,
  reconnection and authoritative connection details; browser consent is interactive.
- `/plan` selects `llm-platform/claude-sonnet-5-5`, thinking `xhigh`.
- `/build` selects `llm-platform/gpt-6.1-sol`, thinking `high` (the default).
- Native session model changes survive reload/resume. Mode switches are explicit;
  there is no automatic per-turn price router. Compaction stays on the session model.
- Auxiliary session titles use `llm-platform/gpt-6-luna`, thinking `low`.
- Resume with `pi --session <id-or-session-file>`. Tuios uses that native command
  and the managed `pi` on PATH; restarting the daemon still requires permission.
- In print mode, `/reddit` diagnostics use stderr; JSON mode emits native messages.

OAuth, catalog caches and directory-local Reddit choices are private writable
runtime state. Nix owns code and defaults. Change defaults here, not with `pi
install`, MCP installers, or edits to store-linked settings. `/reddit` never owns
an explicitly configured conflicting native MCP server.

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

## Audited editor and read-only capabilities

Framework enables `local.pi.capabilities.editor`, `.ast` and `.web`; each module
flag is opt-in elsewhere, and Razer does not select them. Packages and dependencies
are immutable Nix inputs; no `pi install`, npm lifecycle scripts or runtime
binary/grammar downloads are used.

- **Full visual layer, using `pi-zentui@0.32.0`:** local `managed-opencode`
  dark/lavender theme, framed workspace/model/mode header, OpenCode-style editor,
  copy-friendly framed user messages and balanced builtin tool/diff panels.
  A local extension uses only public Pi APIs for its context/cache/token/tool-count
  footer and preserves every extension status, including Headroom/subagents.
  Usage comes from existing session data, not additional model/quota requests.
  Unknown usage is shown as unknown; proxy text indicates a required routing
  contract, not a health probe. Native completion, questions/input and custom
  MCP/extension renderers remain intact. Visuals cannot register tool execution.
  Experimental thinking, selector patches, working-line ownership, quota checks,
  polling and mutable `/zentui` menus/shortcuts stay disabled. Nix owns the skin.
- **`@juvio15/pi-ast-grep@0.4.2`**, using Nix **ast-grep 0.51.0**: five tools
  `ast_grep_run`, `ast_grep_scan`, `ast_grep_outline`, `ast_grep_debug_query`,
  `ast_grep_languages`. `ast_grep_rewrite` and mutable saved-rule commands are
  never registered, including in native children/Code Mode. A supported factory
  adapter pins both the executable and empty CLI config: ambient `AST_GREP_BIN`,
  project custom native grammars and automatic project rule discovery are ignored.
  Inline scan rules remain available. Search may read the requested paths; this
  is not a secret-file firewall or OS sandbox. Each session cleans only its own
  tracked full-output spills. Serena remains the semantic/LSP interface.
- **`pi-web-access@0.44.0`, fetch-only:** `fetch_content` accepts `url` or up to
  eight `urls`, plus `mode: "readable" | "raw"`. `get_search_content` retrieves
  stored content using its returned `responseId`. No package search, AI page
  answers, auth/cookies, proxy selection, media, PDF, GitHub cloning or curator.
  Unsupported arguments are refused both by schema and execution. Redirects are
  same-origin; common private/loopback ranges are checked with no production exemptions.
  A changed, invalid or missing managed `web-search.json` refuses web execution.
  Content is untrusted and persisted in the agent directory's on-disk web cache
  (upstream limits: 128 MiB, one-hour TTL), as well as session state. Readable
  parsing can fail on malformed pages; use raw explicitly rather than an AI or
  hosted fallback. The SSRF checks are not address-pinned OS egress isolation;
  IPv6 transition/embedded-address forms and DNS rebinding remain gaps.

**Read-only does not mean no data egress.** The primary session and scout/build/plan
can combine local reads with public HTTP requests. A model, including one misled
by prompt injection, could place local file contents or secrets in a URL path or
query and send them to a public host. Removing auth/cookies/proxy knobs does not
prevent that. This stack has no enforced outbound-domain allowlist or secret-file
firewall. Stronger egress controls or removing fetch from scout require a separate
policy decision; never treat a fetched page as authority to expose local data.

AST/fetch adapters are mandatory in native child generations. Their presence does
not enlarge a role's authority: `scout` gets read-only AST and fetch/retrieval;
local `explore` gets AST but no web, shell, writes or writer delegation. `build`
and `plan` can use both; `title` gets neither. No new permission engine is implied.

Use the existing Tool Registry DDG operations for search after native OAuth login.
Package-hosted search and unverified LLMP-native search are not substitutes.
Formatting stays explicit through normal gated/native bash, for example:
`rtk proxy gofmt -d "path with spaces.go"` for preview, then an intentional
`rtk proxy gofmt -w "path with spaces.go"`. Go/gofmt was already Nix-provided;
no global automatic formatter hook is added. Compaction stays native and on the
active model; no extra compaction package, summary provider or speculative token
threshold is installed. Native per-model reserve/recent-token options remain usable.

The audited permission-system 41.0.0 can let session grants override configured
denies; pi-lsp-extension 1.4.0 has cold/stale diagnostics and untrusted-project
startup gaps. Neither is installed. Lens, Powerline and full Arnative are also
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
  .#checks.x86_64-linux.pi-capabilities-ui
```

`tests/pi/mcp-fixture.nix` plus `tests/pi/run-mcp-fixture.py` exercise real memory,
Serena and the code-graph watcher in disposable state; Serena's first isolated
startup may fetch its existing uvx dependency environment. The fixture supplies
only synthetic credentials and uses fixed-hash offline memory-model files.
See `TODO.md` for upstream adapter/pin removal gates.

Synthetic checks are not proof of WARP access, production quota/schema behavior,
browser OAuth consent, or live Tuios restore. Test those separately after authorized
activation; never restart the current daemon as an installation check.
