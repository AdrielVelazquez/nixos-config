# Native OMP Reddit Parity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task (recommended here: the tasks share native API and lifecycle interfaces). Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a working native OMP `/reddit` hub with project/model controls, quota and Tool Registry authentication/access, reusing the pinned provider fork where host-independent.

**Architecture:** A Nix-managed source patch exposes extension-owned runtime MCP registrations through OMP's existing manager/tool bridge/OAuth. Local OMP controllers connect the pinned fork's reusable helpers to native menus and the existing mandatory Headroom provider. Native OMP alone owns registry credentials; no managed config file becomes writable.

**Tech Stack:** OMP 18.12.6/Bun/TypeScript, local JavaScript extension modules, pinned Pi provider helpers, Nix/Home Manager, synthetic Python HTTP/OAuth/MCP and PTY fixtures.

**Spec:** `docs/superpowers/specs/2026-10-23-omp-reddit-parity-design.md`

## Global Constraints

- Target `homeConfigurations.cachyos-framework13`; validate on `framework13` / CachyOS x86_64 Linux. Razer remains unchanged and CUDA-heavy full builds are not required.
- Preserve official OMP 18.12.6 at `45c35e40…`; apply the approved focused source patch through Nix. Preserve other OMP/UI overrides and all unrelated lock inputs.
- Use the existing `inputs.pi-reddit-provider` pin `e0131a6…` as behavioral reference; import host-independent modules, not the modern Pi provider entry point or unmodified Pi MCP controller.
- Reddit control-plane root: `https://llm-platform.snooguts.net`; registry resource `/api/mcp`, issuer `/api/oauth`. Model gateway and mandatory owned Headroom routing remain separate.
- Filter `tool:llmp:` from fresh/cached registry scopes and tools. Opt-in is off initially; browser auth is explicit user action, never a model/tool-call side effect.
- Credentials stay in OMP's native vault. Private consent/provider/project state lives only under the selected OMP agent directory. Do not read real credentials or rewrite managed declarations.
- No paid inference, real browser OAuth, activation, merge, push, remote fork or Tuios restart is authorized by this plan.
- Preserve Pi/OpenCode behavior, existing role policy, read-only worker gates, native visuals and unrelated user/agent work. Keep the host-managed worktree intact.

## Review Focus

1. Native login/logout/enable/remove must not replace `mcp.json` symlinks or launch browser auth from model-driven registry calls (Tasks 1, 4).
2. Cached OAuth discovery and native scope precedence must not reintroduce first-party LLMP scopes (Tasks 1, 3, 4).
3. A denied project switch or late old-project catalog response must not combine a new bearer with old metadata (Tasks 2, 4).
4. Directory opt-outs must apply to direct, guessed, stale and `xd://` calls before argument materialization/network I/O (Tasks 1, 3, 4).
5. Reload, parallel children and same-name file/extension servers must not steal or dispose the parent's runtime server (Tasks 1, 4).

## File map

- `packages/omp-path-reddit-mcp-api.nix`: compose the approved patch with the upstream package; no inline installer or replacement recipe.
- `packages/patches/omp-reddit-mcp-api.patch`: native extension/runtime/SDK bridge, owned-manager layer, MCP call policy and owned-auth/config guards.
- `dotfiles/omp/reddit-state.mjs`: OMP project-choice persistence, private atomic files and locks; registry consent/preferences use the fork's existing helper.
- `dotfiles/omp/reddit-services.mjs`: project/quota/status operations and host-independent helper imports.
- `dotfiles/omp/reddit-tools.mjs`: native OMP registry controller, metadata validation, provider inventory and execution decisions.
- `dotfiles/omp/reddit-ui.ts`: command/menu adapter, native model/MCP handoffs and readable headless output.
- Existing `dotfiles/omp/provider-core.mjs`, `work.ts`: transactional project changes and always-installed command orchestration, preserving current transport behavior.
- Existing `modules/home-manager/omp.nix`, `checks/omp.nix`: packaging, runtime options and isolated checks. `docs/omp.md`/TODO/review documents travel with their deliverables.
- `tests/omp/{mcp-native.ts,reddit-services.mjs,reddit-tools.mjs,reddit-ui.mjs,reddit-wire.py,reddit-pty.py}`: dedicated native/controller/protocol/UI coverage. Reuse existing fixture utilities where practical; do not copy the entire wire harness.

### Task 1: Native extension-owned MCP compatibility bridge

**Files:** create the package/patch above and `tests/omp/mcp-native.ts`; modify the native source through the patch only, plus `modules/home-manager/omp.nix` and `checks/omp.nix`.

**Interfaces:** Add OMP-native `ExtensionAPI.registerMcpServer(name, config, policy?): Promise<void>`, `unregisterMcpServer(name): Promise<void>`, and `getMcpServers(): ExtensionMcpServerSnapshot[]`. Registrations are owner-bound by the loader's extension identity plus session generation, not a caller-supplied ownership string. Snapshots contain name, source/ownership, URL, connection/error state, non-secret auth state and raw/native tool metadata; never resolved headers/tokens. `policy({serverName, toolName, cwd}): Promise<{allow:boolean, reason?:string}> | {allow:boolean, reason?:string}` is evaluated before argument materialization or RPC, including deferred/stale tool handles and retries.

```ts
type ExtensionMcpServerSnapshot = {
  name: string;
  source: string;
  extensionOwned: boolean;
  url?: string;
  status: "connecting" | "connected" | "disconnected";
  authState: "none" | "stored" | "error"; // stored is not a claim of working access
  error?: string;
  tools: Array<{ name: string; originalName: string; description: string; readOnlyHint?: boolean }>;
};
```

**Native touchpoints:** Under `packages/coding-agent/src/`, patch `extensibility/extensions/{types,loader}.ts`, `sdk.ts`, `mcp/{manager,tool-bridge,oauth-reauth}.ts`, `modes/controllers/mcp-command-controller.ts`, and shared non-TUI MCP command paths where they mutate server config. Put the owner-layer implementation in new `mcp/extension-servers.ts` rather than expanding a single huge file.

- [ ] **Step 1 — write the native failing witness:** Run compiled unmodified OMP with a fixture extension calling `registerMcpServer` after session start and a fake registry returning `search__lookup`. Assert actual `tools/list` and one successful tool RPC, owner collision refusal, and removal. Add the missing `omp-mcp` check using the current raw package first.
- [ ] **Step 2 — observe RED:** `rtk nix build --no-link .#checks.x86_64-linux.omp-mcp`. Expected failure: native registration API unavailable, not a model/gateway setup failure.
- [ ] **Step 3 — implement the bridge through the patch:** Bind API methods per extension/runtime; use existing `MCPManager.connectServers`, `updateServerConfig`, `disconnectServer` and session tool refresh. Keep a separate owner layer that survives native disconnect/reload and refuses literal/normalized namespace collisions. Children cannot mutate registrations; stale cleanup cannot remove a newer owner generation.
- [ ] **Step 4 — implement owned auth/config handling:** Mark owned entries explicitly in auth lookup. Existing native reauth/refresh/vault remain authoritative; owned entries never write server config, even after old auth material. For owned servers, validated explicit scope wins over discovered/cached scopes (`oauth-reauth.ts` currently gives discovery precedence). Native `/mcp reauth`/`unauth` work; config-mutating enable/disable/remove commands refuse with “manage through the owning extension” rather than writing an override. Suppress automatic interactive auth on tool challenges; report the manual reauth action instead.
- [ ] **Step 5 — extend/run GREEN witnesses:** Assert managed `mcp.json` target/hash/symlink unchanged across auth/cancel/logout and refused config mutations; no automatic browser callback on tool 401; no policy bypass through direct/deferred/xdev/retry handles; native reload preserves the owner layer; parallel/follow-up child disposal preserves the parent; foreign collisions never overwrite files. `omp-mcp`, existing `omp-wire`, exact Framework/Razer evals and raw package install checks pass.
- [ ] **Step 6 — commit:** `feat(omp): expose owned runtime MCP controls through Nix patch`. Include packaging/removal gates in TODO.md and runtime API docs needed by later tasks.

### Task 2: Project, quota and private state services

**Files:** create `reddit-state.mjs`, `reddit-services.mjs` and `tests/omp/reddit-services.mjs`; modify `provider-core.mjs`, `work.ts`, `modules/home-manager/omp.nix`, `checks/omp.nix`.

**Interfaces:** Extend `createProviderService` with `projectStatus(): {id?:string,source:string,status:string,error?:string}`, `previewProject(id,{signal}?): Promise<PreparedProject>` and `commitProject(prepared): Promise<ProviderConfig>`. `PreparedProject` contains validated ID/models and a private generation token; stale/denied previews cannot commit. Expose `createRedditServices({provider, agentDir, controlPlaneOrigin, projectSelection, supportPath}, deps)` returning `status(ctx)`, `quota(ctx,{refresh}?)`, `previewProject(id,ctx)`, `commitProject(prepared,ctx,selectedModel)` and `close()`.

`projectSelection = {id, source:'declared'|'environment'|'default', locked:boolean}` is resolved at runtime using the selected OpenCode package's pure resolver. Nonempty declared/env overrides lock selection; otherwise private canonical-directory choice precedes `opencode-dev`. Project preferences are a separate `reddit/projects.json` schema; retain the fork's `reddit/preferences.json` schema for registry choices. Import the fork's `quota.ts` and exported `formatQuota` through `supportPath` without invoking its extension/provider registration.

- [ ] **Step 1 — add RED service tests:** Assert default `opencode-dev`, locked trimmed declared/env values, separate OMP-only mode-600 state, symlink rejection and concurrent atomic updates. Assert preview does not mutate key/catalog; 403/missing roles/stale generation cannot commit; late old-project refresh cannot publish under a new project. Exact quota fixtures include `usageMicrodollars:'1234567'` → `$1.234567`, hard limit `2000000` → remaining `$0.765433`, hard exhaustion, soft/no quota and UTC rollover.
- [ ] **Step 2 — observe RED:** `rtk nix build --no-link .#checks.x86_64-linux.omp-reddit-core` (introduced here, initially only these tests). Expected missing service/project transaction behavior, with existing provider tests still passing.
- [ ] **Step 3 — implement services:** Validate all project IDs and current/required model availability before changing auth. If the current model is unavailable, require an explicit choice from the candidate catalog or cancel; never silently choose another model. Close over project generations in every discovery callback; rebind the native provider/model together only after a valid preview. Persist the directory choice only on success. Use the same owned transport, no second proxy or direct inference path.
- [ ] **Step 4 — implement quota/state details:** Use bounded trusted-root fetch (`redirect:'error'`, 5-second timeout, bounded body) and the pinned quota parsing/reader/formatter. Cache/single-flight at most the existing 60-second helper policy; stale data remains labeled and project/month-specific. Do not poll quota in the background. Atomically write/lock private project state; never resolve paths into Pi/OpenCode state or managed config.
- [ ] **Step 5 — run GREEN/regressions:** `omp-reddit-core`, `omp-core`, `omp-config`, exact Framework/Razer evals pass. Update config contracts to assert support source provenance and that production Reddit root is HTTPS/public control plane, not the private inference gateway or fixture loopback.
- [ ] **Step 6 — commit:** `feat(omp): add Reddit project and quota services` (consolidate with later OMP controller commits into one logical feature commit at handoff if appropriate).

### Task 3: Full native Tool Registry controller

**Files:** create `reddit-tools.mjs` and `tests/omp/reddit-tools.mjs`; extend `omp-reddit-core` and config contracts. Consume the Task 1 native methods and Task 2 service/state options.

**Interfaces:** `createRedditTools(pi,{agentDir,controlPlaneOrigin,supportPath},deps)` returns `setup(ctx)`, `snapshot(ctx)`, `setProviderEnabled(ctx,id,enabled)`, `signIn(ctx)`, `signOut(ctx)`, `refresh(ctx)`, `showConnection(ctx)` and `close()`. Runtime server name is `reddit-tools`; source owns only that registration. Reuse the pinned private registry-preferences helper, safe diagnostics and applicable inventory logic; adapt native raw metadata explicitly rather than pretending its namespace shape matches Pi's.

- [ ] **Step 1 — add RED controller tests:** Fresh preferences remain opted out with zero registry/network/browser actions. Setup requires confirmation before saving consent. Validate resource `https://llm-platform.snooguts.net/api/mcp`, issuer `…/api/oauth` and ASCII scope metadata. Fresh and cached mixed scopes exclude every `tool:llmp:` value; identity-only fallback is explicit and never asks native discovery to choose all scopes. Malformed/wrong-origin metadata fails closed without overwriting the last valid cache.
- [ ] **Step 2 — observe RED:** `rtk nix build --no-link .#checks.x86_64-linux.omp-reddit-core`. Expected missing controller, not missing native API (Task 1 already passed).
- [ ] **Step 3 — implement registration/inventory:** Explicitly await owned server publication. Connect only after opt-in; do not install static registry config or a helper daemon. Snapshot reports real native connection/error/auth state plus actual advertised provider/tool counts. Only validated same-origin `/api/mcp/upstream-auth/<id>/start` links may be offered from actual authorization tools. Hide first-party providers and respect normalized explicit/other-extension name conflicts.
- [ ] **Step 4 — implement call/consent controls:** Canonical-directory provider toggles use locked private preferences; evaluate fresh choices at each execution boundary before argument materialization/network I/O. Test disabled, guessed, long-name aliases, stale handles and xdev invocation, cross-directory/symlink paths, simultaneous preference updates and corrupt state. Off means no call; missing/invalid state is not permission to broaden. Keep scope discovery bounded/single-flight and only after opt-in, not a quota/model poll.
- [ ] **Step 5 — implement native handoffs:** Sign-in explicitly prepares filtered scopes then offers `/mcp reauth reddit-tools`; sign-out uses `/mcp unauth reddit-tools`; details/reconnect use native commands. Use editor/native command dispatch, never an LLM prompt or fake success. Cancel leaves previous valid credentials/preferences intact. Closing a child/UI must not dispose the main controller/manager/proxy.
- [ ] **Step 6 — GREEN/commit:** `omp-reddit-core`, `omp-mcp`, existing `omp-core` pass; commit `feat(omp): connect Reddit Tool Registry controls` with docs on supported auth ownership and opt-outs.

### Task 4: Native `/reddit` hub and compiled end-to-end proof

**Files:** create `reddit-ui.ts`, `tests/omp/{reddit-ui.mjs,reddit-wire.py,reddit-pty.py}`; modify `work.ts`, OMP Nix module/checks and docs. Reuse/refactor existing test harness utilities without widening production loopback/profile permissions.

**Interfaces:** `registerReddit(pi,{services,tools})` registers `/reddit [status|refresh|quota|tools|project|model]` and the native root menu. Keep `/llmplatform refresh` as a compatible route. Controllers are session-owned; command registration survives a provider setup error and does not store ExtensionAPI/UI contexts in the process-shared provider service.

- [ ] **Step 1 — RED missing-command/menu witness:** Execute compiled patched/configured OMP with `/reddit status` and a native PTY opening `/reddit`, then Escape. Assert registration, meaningful project/model/catalog/error text and a native menu; no model prompt/billing/browser call merely to show the hub. Add `omp-reddit-wire` and `omp-reddit-ui` checks before registering the command.
- [ ] **Step 2 — observe RED:** Build those two checks. Expected unknown `/reddit` or missing menu/handler, not a package/gateway fixture failure.
- [ ] **Step 3 — implement the hub:** Native select/input/confirm with status, project, model, refresh, monthly usage and tools. Model selection uses OMP's real current catalog/native model controls. Project selection supports configured/default, entered ID, saved IDs and explicit personal-project resolution; do not invent an all-projects directory. Respect locked overrides, idle main session and atomic service preview/commit. Print/RPC status/quota are readable; unsupported interactive operations refuse clearly.
- [ ] **Step 4 — compiled fake protocol tests:** Run actual native OAuth PKCE/state/callback success, cancellation, expired-token refresh, logout and actual registry `tools/list`/`tools/call`. Assert requested fresh/cached scopes exclude `tool:llmp:` at both authorization/DCR requests, and no token is sent to inference or model bearer to registry. Assert no sign-in is triggered by a model's tool challenge. Inspect only synthetic OMP credentials/state, immutable file canaries and unchanged synthetic Pi/OpenCode stores.
- [ ] **Step 5 — native lifecycle/policy/routing tests:** Prove runtime server survives MCP/extension reload and two parallel plus one follow-up child; opting out, conflicts, stale handles and xdev cannot invoke disabled providers. Scout/explore mutation/query/delegation ceilings remain. Delay an old-project catalog response across an explicit project switch and assert new-project auth/models remain paired. Both Chat/Responses remain on owned Headroom and killed-proxy tests never bypass it.
- [ ] **Step 6 — PTY/error paths:** Screenshot/text witness for native menu, project input, quota, registry errors, cancelled dialogs and explicit native auth handoff. Test cold interactive metadata/access failure without fabricating usable models, plus mid-session WARP/metadata outage. If upstream cannot open a diagnostic UI without a model, record the actual native blocker and make the smallest additional command-bootstrap fix in the compatibility patch rather than adding fake model availability.
- [ ] **Step 7 — GREEN/commit:** All Reddit/native OMP checks pass with the compiled patched package. Commit the hub/tests/docs; no live browser or paid model test. Consolidate Task 2–4 history if necessary so the command/controller package is one logical unit.

### Task 5: Full verification, review and handoff

**Files:** finish TODO.md, `docs/omp.md` and a complete review/dispositions report; do not edit unrelated skills/config or another agent's branch.

- [ ] **Step 1 — self-review coverage:** Map every spec requirement to a test/artifact, inspect effective Nix package/patch composition and confirm all new imported files are indexed. Confirm unchanged Pi/OpenCode provider pins, OAuth fixes, roles, secrets and helper ownership.
- [ ] **Step 2 — exact eval/build:** Run exact Framework activation, Razer toplevel and Framework system-manager `nix eval`. Run every `checks.x86_64-linux` output except the full `razer14` and `system-cachyos-framework13` builds; the included Framework home check builds activation. Read full failures by name; no undocumented skipped regressions.
- [ ] **Step 3 — one fresh whole-feature review:** Use requesting-code-review after implementation; review the complete source patch/native lifecycle, real auth/config immutability, project transactions, bridge/execution gates and UI parity. The user has not requested a particular reviewer model for this new feature. Preserve the complete report; fix Important/Critical findings with RED→GREEN and the full green suite, record deferred minors, and do not repeatedly re-review the same diff.
- [ ] **Step 4 — learnings/history/handoff:** Run lightweight noninteractive CE capture (skip if code/tests/docs already explain the reasoning), record patch removal criteria, and organize feature history into reversible logical units. Report exact tests and remaining real WARP/OAuth/service-grant verification. Keep branch/worktree; do not merge/push/activate without user permission.

## Plan self-review

- Spec coverage: native MCP/auth ownership → Task 1; project/quota/state → Task 2; registry/providers/scopes → Task 3; actual menu/protocol/lifecycle/routing → Task 4; verification/removal/review → Task 5.
- Interfaces: Task 1's native methods are the only MCP host adapter consumed by Task 3; Task 2 service transaction/status API and Task 3 controller API are the inputs to Task 4's hub.
- All five Review Focus cases have explicit native execution tests, not only source/config assertions.
- No new independent subsystem or separate OAuth/MCP client is proposed. Internal schema/widget choices not pinned above remain normal builder discretion.
