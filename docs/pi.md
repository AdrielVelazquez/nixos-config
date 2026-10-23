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

`scout` uses Sol/low and only audited external read-only GitHub operations;
`explore` uses Luna/low and local read-only file tools. Neither gets shell, writes,
or delegated writer access, including through Code Mode. Missing/auth-denied
research tools must be reported, not replaced by fabricated external research.
Additional approved MCP operations belong in the Nix role options, not wildcards.
Comprehensive web/core-tool parity remains intentionally deferred until actual use.

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
  .#checks.x86_64-linux.pi-tuios
```

`tests/pi/mcp-fixture.nix` plus `tests/pi/run-mcp-fixture.py` exercise real memory,
Serena and the code-graph watcher in disposable state; Serena's first isolated
startup may fetch its existing uvx dependency environment. The fixture supplies
only synthetic credentials and uses fixed-hash offline memory-model files.
See `TODO.md` for upstream adapter/pin removal gates.

Synthetic checks are not proof of WARP access, production quota/schema behavior,
browser OAuth consent, or live Tuios restore. Test those separately after authorized
activation; never restart the current daemon as an installation check.
