# Native OMP review dispositions

Full, unabridged Sonnet 5.5 xhigh review:
[2026-10-23-omp-work-sonnet.md](2026-10-23-omp-work-sonnet.md).
Review baseline: delta after `3b91b22`; official OMP 18.12.6. This companion
records author verification, not a second independent approval.

## Important findings

| ID | Disposition and evidence |
| --- | --- |
| I1 | Fixed: preserve the native `string[]` blocks and append the main-only bootstrap. `tests/omp/extension.mjs` reproduced the comma-coercion failure, then passed. Native wire also checks main bootstrap presence and child absence. |
| I2 | Fixed: validate every search path, reject opaque/internal/mixed URL routes, restrict external reads to canonical scout HTTP(S), and match native `?q` parsing even after `#`. Table-driven tests failed before the policy fix and pass afterward. This is not an OS/network/secret-file sandbox. |
| I3 | Fixed: disable all four implicit local provider IDs. Its config contract failed for Ollama before the change. Auth/acquisition/provider setup errors no longer escape the extension factory and discard its policy handlers; a failing initialization regression now verifies gates and an actionable notification remain. No usable alternate inference provider is registered on failure. |
| I4 | Certification expanded, claims narrowed: native tests load the extension through actual settings, include the production model override and Tuios extension, run actual launcher guards/`--version`, execute GitHub auth with a synthetic env token, and verify real service-helper exec PID/lease/env propagation. The strengthened default-startup witness caught a missing initial catalog; registration now awaits it. MCP endpoints are not live-tested and GitHub SOPS fallback, real Serena `uvx`, memory backend initialization and interactive TUI remain source-derived. |
| I5 | Fixed: child factory registration carries the last complete, header-bearing in-process snapshot, not an empty catalog or native disk-cache rows. Regression failed before the change and passed afterward. Initial startup also awaits a complete catalog. The native wire witness exercises two parallel scouts followed by a third sequential scout. Native background refresh may still perform catalog GETs; no zero-refresh claim is made. |

## All minor findings

- **M1 — documented limitation:** workers have no guaranteed normal MCP/xdev access; the bridge is denied. The direct-name allowlist is not a promise that native discovery advertises those calls. Main-session MCP access is the supported route.
- **M2 — deferred:** schema-structured scout/explore tasks may require `yield`, currently denied. The installed worker definitions are unstructured; structured completion is not certified.
- **M3 — resolved by project parity:** the production entry uses the actual OpenCode 0.4.1 pure resolver. Empty/whitespace environment values use its normal default rather than creating a different project. Generic adapter validation remains strict.
- **M4 — deferred:** direct metadata fetch redirect policy, pre-buffer size enforcement, backoff and richer WARP/HTTP error classification. Current origin is Nix-fixed and requests are bounded by timeout/attempts; this is not stronger redirect/streaming hardening.
- **M5 — deferred:** restart OMP after owned-proxy death; refresh alone does not reacquire it. No direct-inference fallback is permitted.
- **M6 — deferred:** one shared-helper failure still says “Pi” for OMP.
- **M7 — clarified:** skill-summary routing is checked when native summaries occur; tests do not require a cache miss or summary generation on every startup.
- **M8 — deferred:** native OTLP/marketplace defaults are retained. Inherited `OTEL_*` endpoints may export telemetry; configured marketplace plugins may notify about updates. No blanket no-egress claim is made.
- **M9 — retained native behavior:** project and other capability discovery remain enabled. Disabling known foreign providers is not a workspace trust or project-config isolation mechanism.
- **M10 — retained:** native build/plan delegates remain explicitly routed; their tool authority is not the scout/explore ceiling.
- **M11 — deferred:** required model IDs are enforced, but effort availability is not strictly preflighted; native OMP may clamp unsupported efforts. Verify against the real authorized project catalog during the user trial.
- **M12 — documented:** scout `web_search` sends queries directly to DuckDuckGo, not through the model inference proxy. This is ordinary external research, not paid model inference.

## Reviewer-declined questions / author rulings

- Real WARP access, project catalog/efforts and Sonnet payload acceptance require the user's authorized live comparison. Synthetic tests cannot establish them; no paid test or live credential read was performed.
- Real Serena cold-start/`uvx` and memory MCP initialization remain unverified by these fixtures. The service ownership engine is tested independently; that does not certify each server implementation.
- Native `--print` tests do not prove interactive first-frame timing or every TUI workflow.
- Project `.omp`/MCP/agent discovery is a trusted-workspace surface. No adversarial project or host sandbox is claimed.
- Scout's public network research remains enabled, with URL-data egress risk disclosed; local-only explore is separately gated.
- Native telemetry/marketplace policy remains as recorded under M8, not an inference-proxy guarantee.

## Verification status

Author verification after the review fix pass:

- **29/29 outputs built:** Framework Home Manager activation plus every x86_64
  check other than the full Razer and Framework system derivations. This includes
  OMP core/config/native wire, all Pi capability/routing/Headroom/Tuios checks,
  real OpenCode/Headroom and the general formatting/editor/shell contracts.
- Exact Framework Home Manager, Razer NixOS and Framework system-manager evals
  passed. Full Razer/CUDA and system builds were not performed.
- Activated `/nix/store/sc5rf2zwd4qdxlhqjbw948ylmk3zqhdj-home-manager-generation`
  under the user's existing permission; previous generation `7i9s9iin…` retained.
- Verified installed `omp/18.12.6`, all three app executables, `oc` → OpenCode,
  writable mode-600 OMP config and store-linked companion declarations.
- No real model inference, live credential read, Tuios restart, merge or push.
  `zsh -ic` verified the alias but emitted non-TTY ZLE warnings; activation also
  noted that an already-running Zen Browser skips its preference refresh.

The original independent review did not establish these later verification results.

The expanded suite initially exposed `headroom-cli` comparing host-specific
wrapper identities. Both hosts use the identical upstream Headroom closure,
tuning and default flags; Framework's wrapper additionally carries its trusted
LLM Platform origin. The check now compares the unwrapped application identities
and retains its real launcher/runtime tests, rather than forcing Razer's policy
to change.

## Scoped learning maintenance

CE lightweight capture: no additional learning document; the implementation
comments, regressions, `docs/omp.md` and these dispositions already retain the
reusable reasoning. Documentation skipped (no distinct learning).

CE refresh scope: only
`docs/solutions/tooling-decisions/opencode-v2-agent-model-routing-semantics.md`.
Scanned 1; kept 0; updated 1; consolidated/replaced/deleted/skipped/stale 0.

**Applied:** updated the stale “Framework selects Pi” context to match restored
OpenCode alongside Pi/OMP, and linked the separate OMP guide. Routing guidance
was not replaced. The OpenCode pin is unchanged, so the pin-change retirement
condition is not met. Frontmatter validation passed. Mechanical claims flags
for `packages/core/...` and `packages/tui/...` refer intentionally to the pinned
upstream OpenCode source, not missing files in this config repository.

**Recommended:** none. Vocabulary scanned; no qualifying glossary terms, no
`CONCEPTS.md` created. Active agent instructions already surface `docs/solutions`;
no instruction-file changes are needed. The scoped refresh is committed separately.

## Main-branch integration

The user's OpenCode fixes landed while this branch was being prepared for merge:
`75881c9` filters first-party-only Tool Registry scopes and `58b6143` restores
Framework OpenCode alongside Pi. The first fast-forward attempt was rejected
without updating main. Rebasing preserved both commits and the corrected provider
package/runtime OAuth regression test.

Overlapping restoration contracts/docs were combined, retaining the explicit
work-role routing, `oc` → OpenCode, OpenSpec and OMP trial. The combined Home
Manager eval initially failed OMP's old npm-spec assertion (RED). OMP now imports
only the pure project-option resolver from OpenCode's actually selected immutable
package, including its scope correction, instead of separately fetching the old
release. A config regression asserts that exact source provenance as well as the
existing declared/env/default project behavior. No credentials, OAuth state or
incompatible plugin API is shared. The combined Framework/Razer/system-manager
evaluations and **30/30** pre-merge check/build outputs passed, including the
new OpenCode OAuth regression and native OMP wire check. This integration does
not authorize a push, activation, Tuios restart or live inference test.
