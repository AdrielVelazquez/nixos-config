# OMP `/reddit`: review dispositions and acceptance

Scope: `feat/omp-reddit-parity`, based on `main` at `0e8fc89`.
The [complete independent review](2026-10-23-omp-reddit-review.md) is preserved
unaltered. No second review was commissioned.

## Findings

- **I1, Important — accepted:** late discovery must not relabel a live runtime
  connection and remove its guard. Serialize owner/discovery mutations, retire
  the matching old connection, and leave retained handles bound to revoked state.
  `tests/omp/mcp-ownership.ts` covers delayed discovery and live project-config
  reconciliation with the real native manager, not a copied manager mock.
- **I2, Important — accepted:** disabled declarations and native disable lists
  reserve normalized names even when omitted from connected inventory. Native
  discovery carries those reservations into registration and rediscovery.
  `mcp-ownership.ts` and compiled `mcp-native.py --reserved` cover literal and
  normalized declarations/lists, zero requests and unchanged immutable symlinks.
  The controller maps the native refusal to its conflict error and rolls back
  consent granted in the same refused setup; earlier consent is preserved.
- **I3, Important — fixed:** every registry preference read now guards its parent
  private directory before calling the pinned helper. Foreign parent-symlink
  consent and stale-policy tests failed before the fix and passed afterward;
  the focused Node suite passed 40/40. No foreign state or credentials are read.
- **M1, Minor — deferred:** inherited native OAuth rediscovery follows redirects
  and lacks a body-size cap. Controller bounds are narrower; issuer/resource pins
  precede grant actions, not every discovery request. Documented in the API guide
  and TODO.md, without claiming comprehensive discovery bounds.

## Coverage map

| Requirement | Evidence |
| --- | --- |
| Actual command, status, exact quota without inference | `reddit-command.py`; compiled `omp-reddit-wire` |
| Native menus, cancel/confirm, project switch, changed API/auth | `reddit-pty.py`; `omp-reddit-ui`, `omp-reddit-cold` |
| Cold inaccessible default project recovery, no fake models | `reddit-pty.py --cold` |
| Project precedence, denied/stale/opaque transaction and rollback | `provider.mjs`, `reddit-services.mjs`, `extension.mjs` |
| Exact microdollars, UTC rollover, single flight/stale quota | `reddit-services.mjs`, pinned quota helpers |
| Explicit consent, fresh/cached filtered scopes, metadata errors | `reddit-tools.mjs`; `reddit-registry.py` |
| Native PKCE/state/callback, refresh/logout/cancel | `mcp-auth.py`, `reddit-registry.py` |
| Trusted issuer/resource and immutable config | `mcp-auth.py` invalid modes; symlink canaries |
| Actual registry RPC, opt-outs, guessed names and xdev | `mcp-native.py`, `reddit-registry.py` |
| Cached/deferred/retry call guards | Native tool-bridge checks before materialization/RPC/retry; direct/xdev tests |
| MCP/extension reload, foreign replacement, parallel/follow-up children | `mcp-auth.py`, `mcp-native.py --lifecycle` |
| Disabled/normalized declarations and delayed ownership changes | `mcp-ownership.ts`, `mcp-native.py --reserved` |
| Read-only worker/delegation ceilings | `policy.mjs`, existing compiled `omp-wire` worker probes |
| Chat/Responses via owned transport; no killed-proxy fallback | Existing `wire.py`, post-switch PTY canary, Headroom tests |
| Separate private OMP preferences/vault; no Pi/OpenCode changes | Native/configured synthetic-home canaries; unchanged lock and other product paths |
| Nix composition, exact targets and regression outputs | `checks/omp.nix`, composed `old.patches`, exact evals and full check build |

The deterministic ownership probe runs against native source in the package's
real dependency/build environment; the disabled-declaration and ordinary
direct/xdev paths additionally run the compiled CLI. It is not described as a
compiled end-to-end reproduction of every possible discovery timing.

## Rulings and review limits

These retain all implementation rulings and every declined-to-judge item:

1. A synchronous optional `policy.isVisible` filters definitions separately from
   asynchronous execution authorization. Execution always rereads state. Cost if
   wrong: stale display until refresh, never permission based solely on display.
2. Task 2 TDD overlapped the Task 1 build wait in this session; it consumed no
   pending MCP interface. Cost if wrong: integration rework, not premature success.
3. Foundation tasks were committed together because bootstrap/model/state
   interfaces were one coherent unit; final feature history is consolidated into
   a reversible implementation unit. Cost if wrong: coarser selective revert.
4. Live WARP/project grants and real personal-project provisioning remain
   unverified: only synthetic services were authorized. Cost: live access may fail.
5. Real browser/SSO approval, client policy, service grants and revocation remain
   unverified. Cost: production sign-in may need external approval or fixes.
6. Real quota values, paid availability and charges remain unverified; no paid
   requests were made. Cost: synthetic arithmetic/routing cannot certify billing.
7. The author, not the reviewer, owns final eval/full-suite evidence. No review
   verdict substitutes for those results. Cost: undetected deployment integration.
8. Activated Framework/Razer/system-manager, real-home symlinks and SOPS-backed
   commands were deliberately not tested. **No activation is authorized.** Cost:
   deployment behavior still needs a separately approved validation window.
9. I1/I2 needed new order/disabled-shape witnesses; both were accepted as findings,
   not dismissed because ordinary reload tests passed. Cost: additional test/build
   work, with retained-handle and native disabled-config coverage required.
10. General upstream OAuth/MCP security, arbitrary hostile extensions and all HTTP
    metadata variants are outside this feature audit. M1 is explicitly deferred.
    Cost: inherited upstream risks remain; no comprehensive security claim.
11. Tool gates are not OS sandboxing, secret confinement or exfiltration prevention.
    Cost: normal host-process authority remains available outside those gates.
12. Real workload performance and later upstream patch availability were not
    measured/re-certified by the reviewer. Existing targeted upstream audit and
    patch-removal criteria stand. Cost: revisit the exception on dependency updates.

No activation, merge, push, live OAuth, paid inference or Tuios restart was done.
The running Pi from `main` is outside this change and must remain untouched.
