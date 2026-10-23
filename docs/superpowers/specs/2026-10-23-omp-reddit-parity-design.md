# Native OMP `/reddit` parity

Status: approved by the user on 2026-10-23, including the Nix-managed OMP source
compatibility patch. Builder check: no important questions left. Branch:
`feat/omp-reddit-parity`, based on `main` at `0e8fc89`.

## Intent and agreed scope

The user wants **full Pi parity**, not merely a command alias: project/model
selection, model status/refresh, monthly quota/usage, and Tool Registry setup,
sign-in/out, authorized tool access, provider controls and connection diagnostics.
OMP keeps its native UI. Its credentials and preferences remain independent of
Pi/OpenCode. This closes an implementation gap in the existing OMP trial.

Target config: `homeConfigurations.cachyos-framework13`. Validation host:
`framework13` / CachyOS x86_64 Linux. Validate that exact activation derivation,
`nixosConfigurations.razer14.config.system.build.toplevel.drvPath`, and the matching
Framework system-manager derivation; run the existing 30 check/build outputs plus
new Reddit checks. Do not build Razer/CUDA merely to validate this feature.

No automatic merge/push, remote fork, real browser OAuth, paid inference, live
credential inspection, system activation or Tuios restart is included. These
require separate authorization. Keep the concurrent UI agent's work intact.

## Source of truth and actual parity boundary

Use the locked Pi provider at `e0131a6af1165b4a0a53930c430d527fc1db16c5` as
behavioral reference, not as a drop-in OMP extension. Its `src/reddit-ui.ts`
currently implements `/reddit [status|refresh|quota|tools]`, and hands sign-in/out
to native Pi MCP controls. Native model/auth UI owns its other selection flows.
The requested OMP hub will additionally expose explicit project/model entry
points rather than pretending Pi's current `/reddit` already implements them.

Pi reference source: `/nix/store/2dvrkdzi659jxvd3zxi78yziwnwy77pl-source`.
OMP reference source: `/nix/store/yalkwd8qj6ybb3mlkv6ama26i2h64prg-source`.
These are research references, not paths to hard-code into product declarations.

The supported OMP APIs already provide commands, native select/input/confirm,
model selection and tool hooks. OMP 18.12.6 does **not** expose Pi's dynamic
MCP registration/inspection APIs. Current upstream `main`'s extension type surface
also lacks them; simply updating the pin will not supply the missing interface.
Upstream discussion https://github.com/can1357/oh-my-pi/discussions/14557 documents
the broader Pi/OMP MCP compatibility question, not an implemented fix.

The user's follow-up confirmed the important ownership split: Reddit behavior
lives in the configured provider fork; Pi supplies MCP/OAuth host capabilities;
Nix pins/installs it. Prefer importing the fork's host-independent quota/formatting,
metadata and private-preferences helpers from the existing pin over copying them.
Do not load its modern Pi provider entry point. Its current Tool Registry
controller hard-codes `.pi/mcp.json` and Pi MCP commands, so it cannot be loaded
unchanged against OMP or be allowed to inspect/manage Pi's configuration.

Native MCP auth currently writes server config in several paths. Its
`mcp/config-writer.ts` atomically renames a replacement file, which could replace a
managed symlink. New runtime-owned servers must never take that path.

## Approved architecture (proposed by the builder)

Use an OMP-native extension/controller plus a narrowly scoped source compatibility
patch, packaged through the existing official Nix source recipe. Keep 18.12.6 as
the baseline and retain CUDA/screencast exclusions. Do not recreate OAuth or a
second full MCP stack in a sidecar, load Pi's incompatible provider API, or edit
anything under the installed skill/application source in place.

The patch supplies a session-scoped MCP facade backed by OMP's **existing**
MCPManager, native tool bridge and OAuth engine. It is a new compatibility surface,
not an assertion that these extension APIs already exist. The facade must support:

- Register/update/remove an extension-owned runtime server, with explicit source
  ownership, name-collision refusal and ordinary native tool refresh.
- Inspect connection/auth/error state and raw tool metadata for provider inventory.
- Enforce a registry-specific execution predicate at the actual MCP call boundary,
  not merely hide definitions. Guessed names and `xd://` must not bypass opt-outs.
- Reuse native sign-in/out, token refresh, cancellation and profile-keyed credential
  storage. Runtime-owned server auth must write credentials only, never `mcp.json`
  or another managed declaration. Config-mutating native MCP commands must either
  operate through the runtime owner or refuse clearly; they must not create a
  shadow user/project server definition.
- Preserve runtime registration across native MCP reload and avoid child sessions
  unregistering or disposing their parent's server. Registration/mutation and
  browser authorization belong to the main session, not model-driven workers.

The implementation plan must settle exact facade signatures and native hook
locations before coding. Keep source changes in a separate
`packages/omp-path-reddit-mcp-api.nix` plus a focused patch file; compose with other
OMP overrides rather than replacing another agent's UI work. Record upstream
evidence, removal conditions and target config in TODO.md. If a suitable supported
upstream implementation is found during the planning spike, prefer it and revise
this design rather than retaining an unnecessary local patch.

## User-facing behavior

`/reddit` opens native OMP menus with status, project, model, refresh, monthly usage
and Tool Registry entries. Explicit subcommands support status/refresh/quota/tools
and project/model selection. Native `/model` and `/mcp` handoffs are fine when
accurately labeled; these must not submit text as a model prompt or fake a
successful operation. Retain `/llmplatform refresh` as a compatibility alias.

Status reports the actual project ID and selection source, selected model/effort,
catalog availability/error, owned inference transport, and actual registry state.
Do not print bearer tokens or imply that a configured connection is authenticated.
Headless status/quota commands produce readable text or native structured output;
interactive-only operations fail clearly without modifying configuration.

Project selection uses a validated project ID, saved prior selections and an
explicit personal-project action where supported. Do not invent an authoritative
"all projects" list. Proposed precedence: explicit Nix project or nonempty
environment override stays authoritative; otherwise an OMP directory-local user
choice precedes the existing OpenCode-compatible default. Display and explain any
locked override. Project changes are idle-main-only, preflight access and required
role models, and commit key/catalog selection atomically. A denied/missing project
must never reuse the old project's catalog under a new bearer or silently fall
back to personal/another model. Preserve mandatory Headroom routing on every model.

Quota uses the caller's monthly QuotaService RPC, validating project, subject,
UTC month and integer microdollars. Show hard/soft limits, remaining amount and
reset date correctly. Cache briefly and single-flight requests; preserve a visibly
stale reading only for the same project/month. No background quota polling or
model requests are required for this UI. Reuse framework-neutral pinned Pi helpers
only after checking runtime imports; keep OMP-specific orchestration local.

## Tool Registry and authorization

- Opt-in is initially off. An explicit user confirmation enables the registry;
  merely opening OMP/status must not launch a browser or silently authorize tools.
- Use the trusted registry root/resource/issuer, not a URL supplied by a workspace
  file or a tool description. Fetch bounded metadata and validate resource/issuer.
- The Nix-declared Reddit control-plane/registry root defaults to Pi's trusted
  `https://llm-platform.snooguts.net`; resource is `/api/mcp` and issuer `/api/oauth`.
  Keep it distinct from the existing private model gateway origin. Project/quota
  operations use the control plane; model inference still uses the selected model
  gateway through owned Headroom. Never send model project bearers to a registry
  endpoint or registry OAuth tokens to inference endpoints.
- Filter `tool:llmp:` scopes from **fresh and cached** discovery. Ordinary dynamic
  client registration must not request first-party scopes or expose LLMP tools.
  Preserve the already merged OpenCode/Pi scope fixes; do not weaken server policy.
- Native OMP owns browser flow, PKCE/state, cancellation, refresh and sign-out.
  Credentials stay in its runtime vault; no copied Pi/OpenCode auth, plaintext
  token preferences, Nix-store secrets, or logs containing credentials.
- Discover actual provider IDs/names/tool counts, validated advertised upstream
  sign-in links, and authoritative connection errors. Do not fabricate services.
- Provider on/off preferences are canonical-directory-local and persisted privately
  with atomic updates/locking. Global consent and directory choices remain distinct.
  Disabled and first-party providers are blocked at execution as well as hidden.
- Existing explicit or other-extension `reddit-tools` definitions are conflicts,
  not permission to replace them. The UI explains the conflict without modifying
  declarations or auth belonging to another integration.
- Scout/explore retain their current deterministic read-only ceiling; opting in
  must not grant registry mutation/shell/delegation through inherited or xdev tools.

## Nix and runtime ownership

Nix owns extension/helper code, the compatibility patch, static service roots and
declarations. Only native credentials and narrowly defined consent/project/provider
runtime state are writable under the selected OMP agent directory, with restrictive
permissions and no symlink-following overwrite. Never write the real home during
tests, run an imperative installer, or rewrite managed `config.yml`/`mcp.json` to
make this work. Use the actual selected patched OpenCode package only for its pure
project-option resolver as before; this work does not replace its OAuth fix.

Closing a UI, cancelling login, reloading extensions, changing projects, spawning
parallel/follow-up workers and exiting processes must leave ownership consistent.
No resident service, secret firewall or OS isolation guarantee is introduced.

## Verification and acceptance

Use TDD for controller behavior, source compatibility hooks and the original
missing-command regression. Run the **compiled, configured OMP** against synthetic
gateway/quota/registry/OAuth servers in Nix isolation, not just mocked callbacks.

Required coverage: `/reddit` dispatch and native menu/cancel; project precedence
and atomic failed switches; exact quota arithmetic/month rollover; consent off;
fresh/cached scope filtering; native fake OAuth success/cancel/refresh/logout;
actual discovered tool calls; directory opt-outs including guessed names/xdev;
malformed metadata and denied auth; reload/child lifetime; readonly worker gates;
immutable config canaries and separate auth state; both model APIs via owned
Headroom and no direct inference fallback. Include a real PTY witness for the
native menu, without skinning OMP or opening a real browser.

Run exact Framework/Razer/system evaluations, the Framework activation build,
all existing check outputs and new Reddit checks. A passing synthetic suite does
not certify the user's real WARP authorization, browser approval or service grants;
report those remaining live checks explicitly. Full parity is not complete while
Tool Registry access is only a static stub or command text with no working path.

## Non-goals and builder discretion

Do not change Pi/OpenCode behavior, UI skins, title/skill-summary policy, Tuios
question reporting, model pricing/routing roles, or unrelated lock inputs. No
automatic upstream PR/fork publication. The builder may choose internal module
boundaries, exact native menu widgets and cache implementation, but may not trade
away the approved feature set, credential separation or execution/config guards.
