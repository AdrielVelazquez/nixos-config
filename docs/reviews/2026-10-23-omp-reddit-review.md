# Whole-feature review: native OMP `/reddit` parity

## Scope and evidence

Reviewed branch `feat/omp-reddit-parity`, HEAD `16aa2fec53862385419c1d79eafcca6f893aab89`, against `0e8fc89`, including `git diff HEAD` and staged new controller/UI/test files. Read the approved design, implementation plan, ledger, all requested product files, relevant tests, native implementation surrounding the patch, and the pinned provider helpers actually imported at runtime. The prototype source was used for contextual native line references; the repository patch remains the product artifact.

No repository, index, HEAD, installed configuration, credential database, or running system was changed. No app, browser, live service, build, activation, publication, or delegate was launched. The only retained review artifact is this report. Synthetic probes used temporary directories under `/tmp/opencode` and in-memory fetch/manager implementations, not live network requests or credentials.

Evidence labels below distinguish:

- **Reviewer-executed:** the six existing Node test files passed **38/38**, with zero failures/skips, using Node 24 and the pinned support source. Command: `OMP_REDDIT_SUPPORT=/nix/store/2dvrkdzi659jxvd3zxi78yziwnwy77pl-source/src <node-24>/bin/node --test tests/omp/provider.mjs tests/omp/policy.mjs tests/omp/extension.mjs tests/omp/reddit-services.mjs tests/omp/reddit-tools.mjs tests/omp/reddit-ui.mjs` (through `rtk proxy`). Two additional synthetic probes are described in the findings.
- **Supplied executed evidence:** the parent's baseline/foundations suites and compiled native MCP, OAuth, lifecycle, configured registry, command and PTY witnesses. These were inspected through their test sources and the provided ledger/task context, not independently rebuilt here.
- **Source reasoning:** consequences traced through the actual implementation, without claiming a compiled end-to-end reproduction.

## Findings

### Important I1 — Late explicit discovery can relabel a live runtime connection and remove its execution policy

**Location:** `packages/patches/omp-reddit-mcp-api.patch:300–307` (`ExtensionMcpRegistry.merge`), with `:247–249` (registration collision lookup). Relevant existing native behavior: prototype `packages/coding-agent/src/mcp/manager.ts:807–820`; deferred discovery publication: `packages/coding-agent/src/sdk.ts:2646–2673`.

**Evidence:** Source reasoning plus a reviewer-executed, source-derived synthetic probe. The probe transpiled the actual changed `extension-servers.ts`, preserving its registry/guard logic, and supplied an in-memory manager with the source-overwrite/skip-connected behavior directly present at native `manager.ts:807–820`. It did not execute the compiled native CLI.

The failing order is:

1. An opted-in extension registers `reddit-tools` while initial file discovery is still pending; `getAllServerNames()` does not yet contain the explicit declaration.
2. Its registry transport connects and receives native tools, with the owned source and execution policy.
3. File discovery supplies an explicit server with the same literal name. `merge()` marks the runtime entry inactive but does not detach its transport or tools.
4. Native `connectServers()` overwrites the existing connection's `_source` with the file source, then skips reconnecting because that name is already connected.

The transport is still the runtime registry transport, but it now claims file ownership. `checkExtensionMcpCall()` immediately returns for that non-`omp-extension` source. This is not just a false status label: directory opt-outs and the first-party denial can be bypassed on those surviving runtime tool objects. The deferred SDK also publishes the returned tool snapshot.

**Observed synthetic result:** initial policy denial `true`; denial after late explicit discovery `false`; actual connected URL still `https://control.invalid/api/mcp`; claimed source `mcp-json`; snapshot ownership `false`. The real asynchronous discovery path establishes reachability by source; its timing was not reproduced with the compiled app in this review.

**Effect:** A startup discovery race can both steal the logical identity of an explicit server and strip the safety policy from the original registry connection. The existing foreign-replacement witness uses `/mcp reload`, which first disconnects everything, and therefore does not exercise this order.

**Fix:** Serialize runtime registration with initial discovery and source-changing native reconciliation. On a collision, detach only the matching old runtime connection/tools before publishing the explicit server; never change an existing runtime connection into a file-sourced connection in place. Audit live project-config reconciliation as well as full reload, since it also calls `connectServers()` without the owner-layer merge. Add a compiled delayed-discovery regression asserting the correct endpoint/source and denial of disabled/LLMP calls through retained handles and `xd://`.

### Important I2 — Disabled explicit declarations and native disable lists do not reserve their namespace

**Location:** `dotfiles/omp/reddit-tools.mjs:52–58`; `packages/patches/omp-reddit-mcp-api.patch:247–249,300–307`.

**Evidence:** Source reasoning. Native `mcp/config.ts:128–165` constructs disable lists, suppresses disabled declarations, and returns only surviving capability items as `configs`/`sources`. `capability/index.ts:252–297` excludes suppressed items from those results. The new collision checks inspect only live manager names/snapshots or that already-filtered config map.

Consequently, a user/project declaration such as `mcpServers.reddit-tools.enabled = false`, or a user `disabledServers` entry for that name, can disappear from every collision input. The extension can then register an enabled runtime server under the reserved name. Subsequent reload merges the runtime config after native disable filtering, so the disable does not stop it either. The current Node collision fixture inserts a visible server snapshot; it does not represent this native filtered-declaration case.

**Effect:** A deliberately disabled explicit integration is silently shadowed by the extension. Files remain unchanged, but configuration ownership and the operator's disable decision are not respected. This violates the expected conflict behavior even without the race in I1.

**Fix:** Carry declared/reserved namespaces and disable decisions from native discovery into the owner registry, including disabled entries within enabled discovery scopes. Refuse registration with a clear conflict/disabled explanation rather than treating absence from the connected inventory as absence of a declaration. Cover literal and normalized names, `enabled:false`, and `disabledServers`, with immutable-config canaries and zero registry authorization actions.

### Important I3 — Registry preference reads follow a symlinked `reddit` directory and import foreign consent

**Location:** `dotfiles/omp/reddit-tools.mjs:21,38–45,60–67,83`; compare the directory guard in `dotfiles/omp/reddit-state.mjs:22–31`.

**Evidence:** Reviewer-executed synthetic controller probe using the actual pinned preferences helper. The helper's `src/reddit-state.ts:29–39` uses `O_NOFOLLOW` on `preferences.json`, but does not validate its parent directory on reads. Its update path validates that directory only later, when acquiring the write lock.

The probe created an otherwise fresh synthetic OMP agent directory whose `reddit` entry was a symlink to a separate synthetic directory containing `toolsOptIn:true`. Calling the real controller's `start()` imported that consent, invoked the mocked native registration API, and attempted mocked metadata discovery without asking for confirmation. Snapshot reported `configured:true`. No real Pi state, credentials or network was used. Fresh execution-policy reads follow the same parent symlink, so this is not limited to display state.

**Effect:** OMP can automatically connect based on another directory's consent/preferences instead of its own private state. A later write refusal does not undo the earlier registration or make the execution predicate fail closed. The stronger project-state reader already rejects this directory shape, but the registry reader does not.

**Fix:** Guard the selected agent directory's `reddit` state directory before every preferences read, including call-boundary policy reads; reject symlink/non-directory/foreign-owned state rather than importing it. Preserve the missing-state, initially-opted-out behavior. Add a controller test with `reddit -> synthetic foreign state`, asserting no registration/discovery and denied stale calls. Keep the pinned preference schema/helper reuse; a local guarded adapter is sufficient.

### Minor M1 — The metadata bound does not extend to native OAuth rediscovery

**Location:** `packages/patches/omp-reddit-mcp-api.patch:479–492`; bounded controller fetch: `dotfiles/omp/reddit-http.mjs:10–29`.

**Evidence:** Source reasoning. The controller's metadata request is correctly origin-constrained, redirect-refusing, deadline-covered and capped at 1 MiB. Explicit native reauthorization independently runs `resolveMcpOAuthEndpointsFromServer()` before the added issuer/resource checks. Existing native `mcp/oauth-discovery.ts:536–547` follows redirects and decodes metadata with `response.json()` without a body-size cap; subsequent metadata requests use the same native discovery behavior. The controller wrapper is not involved there.

**Effect:** Issuer/resource pins prevent acceptance of the wrong metadata before browser/DCR/token actions, but do not make that native metadata phase bounded in size or redirect-confined. An oversized/misdirected metadata response can still consume substantial memory or cause discovery requests before refusal. This is an inherited native behavior reached by the new integration, not evidence of a currently malicious service or credential leak.

**Fix:** For runtime-owned pinned servers, constrain/bound the native metadata-fetch path too, or explicitly document this narrower limit until that scoped hardening is implemented. Add an oversized-body/redirect synthetic witness before claiming that all OAuth discovery is bounded.

## Coverage and positive findings

These conclusions do not cancel the demonstrated successful paths:

| Area | Review conclusion and basis |
| --- | --- |
| Native auth/config immutability | The new owned lookup, credential-only success branch, logout branch, config-writer guards and native mutation refusals address the ordinary write-back paths. Supplied compiled PKCE/refresh/cancel/logout and immutable-symlink evidence supports them. I1/I2 identify additional ownership orders, not a claim that those witnesses failed. |
| No automatic browser on registry calls | The native bridge refuses owned result challenges and the manager suppresses its interactive auth handler for owned servers. UI handoffs edit the composer and explicitly require Enter. Supplied native/configured browser-stub evidence is consistent with the source. |
| Scope filtering | Fresh/cached controller scopes exclude `tool:llmp:`; an explicit identity-only fallback avoids discovery selecting all scopes. Native scope override applies to authorization URL parameters and DCR. Issuer/resource pins are checked before those grant actions. M1 concerns the preceding native metadata-fetch boundary. |
| Project precedence and normal transactions | Declared/nonempty environment overrides remain locked; default selection can use a saved directory choice or explicit personal/entered project. Opaque prepared tickets, generation checks and rollback protect ordinary denied/stale switches. Per-row authorization keeps old in-flight rows paired with old project metadata. Node tests passed these paths. |
| Post-switch native inference | The supplied PTY witness and current source exercise changed model API/auth through the owned transport. The parent was still finalizing the canary assertion; this review does not claim that final check or the entire suite passed. Accepted native Luna title/skill-summary requests are not unauthorized inference. |
| Quota | Reuses the pinned parser/reader/formatter, caller subject and project checks, exact integer-microdollar formatting, single flight, short cache and UTC-month-specific stale handling. Reviewer-executed Node fixtures passed; supplied CLI/PTY evidence exercises presentation. No background quota polling was added. |
| Execution boundary | With source identity intact, direct/deferred/retry guards run before outbound argument materialization and immediately before RPC. Controller execution rereads canonical-directory preferences, rather than relying on hidden definitions. Supplied compiled direct/xdev/first-party denials support this. I1 is a source-identity escape from that otherwise sound boundary. |
| Children and normal reload | Child registration mutations are main-only, child controllers do not start/close the parent registry, and manager ownership remains with the parent. Stale owner cleanup preserves a foreign replacement. Supplied two-parallel-plus-follow-up and reload witnesses support these ordinary paths. |
| Packaging and isolation | The focused patch composes `old.patches` with the existing official package recipe. No Pi/OpenCode source/pin changes or managed config replacement were introduced. The imported support helpers are framework-neutral at runtime; the modern provider entry point and unchanged Pi controller are not loaded. Private project-state writes use locking/atomic replacement and reject symlinks. I3 is specifically the separate registry preference-read gap. |
| Native visuals and workers | UI uses native select/input/confirm/model/MCP controls. Existing scout/explore policy ceilings remain installed even after provider setup failure; registry opt-in does not add exceptions to them. No skin or new OS-isolation claim was introduced. |

No Critical finding was established. There are three Important findings and one Minor finding. Passing existing tests do not cover the failing declaration/state shapes above.

## Declined-to-judge behaviors and limits

All declined judgments are listed here before the verdict:

1. **Live WARP identity/project execution grants and real personal-project provisioning:** only synthetic services are authorized; no live identity, credential or control-plane inspection was performed.
2. **Real browser/SSO approval, production OAuth client policy, upstream service grants and revocation propagation:** browser stubs/native callback witnesses do not establish these external permissions; no real login was authorized.
3. **Production quota correctness or paid model availability/charges:** parser/arithmetic and synthetic routing were reviewed, not real billing data or paid requests.
4. **Final complete Nix/check-suite status, exact final activation build, and final post-switch canary result:** these remain the parent's verification task. This reviewer ran only the 38 Node tests and the described synthetic probes; it neither rebuilt nor polled the parent's jobs and does not infer full-suite success from isolated retries.
5. **Activated Framework/Razer/system-manager behavior, real managed-home symlinks and real SOPS-backed MCP commands:** no build/switch/activation or real-home credential/config examination was authorized. The source targets and synthetic canaries are not a claim of deployment verification.
6. **Compiled end-to-end timing of I1 and native disabled-declaration reproduction of I2:** their mechanisms are supported by native source; I1 additionally has an extracted-code synthetic witness. Neither is misrepresented as a fresh compiled-CLI reproduction. Add those focused witnesses when fixing them.
7. **General native OMP OAuth/MCP security outside the owned registry path, arbitrary extension hostility, unsupported profiles and all possible HTTP metadata variants:** this is a whole-feature review, not a full upstream security audit. M1 records the concrete inherited boundary gap found; the supplied issuer/resource witnesses do not certify every variant.
8. **OS sandboxing, secret-file confinement and exfiltration prevention:** the feature does not provide those guarantees, and this review does not infer them from tool gates or owned inference routing.
9. **Performance/resource impact under real workloads or upstream patch availability after the recorded investigation:** no live workload measurement or new upstream/network research was authorized or performed. The existing targeted pin and removal documentation were reviewed as source artifacts, not re-certified against current remote state.

CE capture was considered in non-interactive/lightweight mode: **Documentation skipped**. This is an unresolved read-only review, not a solved/verified implementation lesson, and repository writes were expressly forbidden.

## Verdict

**Request changes for I1–I3.** The feature's ordinary UI, project/quota, native OAuth and guarded execution paths have substantial source/test support, but explicit-definition ownership and private-consent handling still have important uncovered failures. Fix them with focused RED→GREEN witnesses, then run the planned regression verification. M1 may be scoped/documented as a deferred minor, without claiming a stronger metadata bound than implemented. No activation, merge, push or live-auth permission is implied.
