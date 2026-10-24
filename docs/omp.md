# Native Oh My Pi work-profile trial

Framework installs source-built **OMP 18.12.6** alongside OpenCode and upstream Pi:

- `omp`: native Oh My Pi UI and work profile.
- `oc` / `opencode`: restored OpenCode work profile (fresh shell refreshes `oc`).
- `pi`: upstream Pi trial, unchanged by OMP.

The official OMP flake is pinned at release `v18.12.6` / `45c35e40…` and builds
its CLI and Rust addon through upstream's Nix recipe. CUDA and optional Wayland
screencast extras are off. No release-binary installer, new cache trust, app fork,
or copied Pi/OpenCode plugin is used. Razer does not enable this trial.
The `/reddit` integration composes a focused [runtime MCP compatibility
patch](omp-reddit-mcp-api.md) with that source recipe; it does not replace native
visuals or OAuth.

## Reddit hub

`/reddit` opens native OMP controls. Available subcommands:

- `/reddit status`: actual project/source, model/thinking, catalog, required
  Headroom transport and registry state. No quota or model request is needed.
- `/reddit refresh`: refresh the model catalog; `/llmplatform refresh` remains an alias.
- `/reddit quota`: caller's exact monthly usage, hard/soft limits and reset date,
  using the pinned provider fork's reader/formatter. Quota is not background-polled.
- `/reddit model`: hand off to native `/model` selection (press Enter).
- `/reddit project [id]`: configured default, explicit personal project, entered
  ID or previously saved IDs. Explicit Nix/environment project overrides stay
  authoritative. Changes require an idle main session with no running jobs and
  an available model; rejected changes do not save a directory preference.
- `/reddit tools`: Tool Registry status, real provider inventory and per-directory
  on/off controls. Setup requires explicit confirmation; it starts opted out.
- `/reddit tools setup|login|logout|refresh|details`: interactive shortcuts.
  Native MCP handoffs require Enter; OMP owns browser OAuth, cancellation, refresh
  and its own credential vault. `/reddit tools provider <id> on|off` toggles here.

Tools use the trusted public Reddit control plane, separately from the private
model gateway. Fresh/cached discovery and native auth exclude first-party LLMP
scopes/tools. Provider opt-outs are enforced before actual calls, including xdev
and guessed names, not merely hidden in a menu. Disabling a provider does not
revoke its upstream account grants. Existing conflicting MCP definitions are
reported, never overwritten; registry OAuth does not rewrite managed `mcp.json`.
A disabled `reddit-tools` declaration or `disabledServers` entry still reserves the
name: setup reports the conflict and rolls back its new consent rather than
registering over it. Declarations added later retire the runtime server instead of
relabelling its connection.

OMP's private `reddit/preferences.json` and `reddit/projects.json` hold consent,
provider choices and canonical-directory project selections, not credentials or
resolved bearers. Native model rows bind their runtime project authorization so
old in-flight metadata cannot be paired with a newly selected project's bearer.
Nothing copies Pi/OpenCode preferences or auth. Commands reject worker mutations;
print/RPC supports readable diagnostics, while interactive changes require the UI.

The source patch plus controllers are tested with compiled OMP, native PTYs,
fake browser/PKCE/token endpoints, actual registry RPCs and managed-config canaries.
These tests do not certify live WARP access, service grants or a real browser login.
Installing/applying this profile still requires the normal activation approval.

## LLM Platform and Headroom

The OMP-native `llmplatform` provider uses the restored OpenCode gateway origin.
WARP supplies identity. The adapter reuses only OpenCode 0.4.1's pure option
resolver—not its plugin API—so project selection has the same declared-option,
`LLM_PLATFORM_PROJECT_ID` and `opencode-dev` default precedence. It does not
silently provision a different personal project. The generic adapter's optional
personal-project RPC is exercised separately but is not this profile's default.
The runtime bearer never enters the Nix store or another harness's DB.
No copied OpenCode/Pi auth file is required. Test real WARP/project access yourself;
the automated checks use synthetic services and never bill a real model.

Catalog requests go directly to the trusted gateway. Native
Chat and Responses model requests use a privately owned Headroom proxy, with
the original gateway path preserved. A dead proxy is an error, not permission
for direct inference. OMP has its own process-lease namespace; native in-process
tasks do not release it when a child session ends, and re-exec processes acquire
their own lease. A process exit cannot preserve work that OMP itself keeps in
that process.

`/model` uses the discovered catalog. `/llmplatform refresh` refreshes it. For a
cold CLI selection of an extension-provided model use separate flags:

```sh
omp --model llmplatform/gpt-6.1-sol --thinking high
```

This avoids native 18.12.6's pre-extension rejection of a cold direct `:effort`
CLI selector. Declarative model-role selectors still use native `:effort` syntax.
Configured work-role models must exist; no guessed/other-model fallback is used
to conceal a missing role. Cold offline catalog availability is not guaranteed:
native disk cache strips routing headers, so the adapter safely refetches.

## Compatible work settings

Default/build/task use Sol high; native plan mode uses Sonnet xhigh; scout uses
Sol low and local explore uses Luna low. Original Superpowers and exactly two CE
skill trees plus six OpenSpec skills/commands are available, with a main-only
bootstrap and native `ask`/`task`/`todo`/`bash` tool mapping. Native OMP visuals
and system prompting are retained; no Pi skin is loaded.

Native MCP declarations provide GitHub (runtime SOPS header command), Headroom
CCR/stats, Headroom memory and isolated Serena. The graph watcher uses the actual
project root; it is not a fabricated graph-query MCP. Native MCP exclusively owns
memory tools, with proxy memory interception disabled. Existing memory stores and
legacy paths are retained, never migrated or reset by this installation.

Scout/explore have explicit native tool-call gates because OMP markdown tool lists
do not remove inherited MCP/extension tools. Shell, edit/write, eval, delegation,
unknown/custom mutations and model-powered read queries are refused. The xdev
write bridge is also refused for those workers; use the main session when that
bridge is required. Workers have no guaranteed normal MCP access; their default
definitions are unstructured, and schema-driven `yield` completion is not certified.
Explore read/search stays local; scout can read canonical HTTP(S) URLs and its
`web_search` queries go directly to DuckDuckGo. This is not OS isolation, a secret-file firewall or an
exfiltration guarantee: local-read plus public requests can transmit URL data.

Accepted native differences:

- Luna titles run without reasoning, not OpenCode's low-effort title setting.
- OMP caches model-generated skill-description summaries. These extra Luna
  requests also disable reasoning and use the owned proxy; the user explicitly
  retained this standard behavior for the trial. Skill sources are unmodified.
- Tuios reports OMP turns and approvals, not general ask-dialog Inbox state;
  automatic OMP conversation resume is not claimed. Answer questions in its pane.
- Native same-model retry defaults remain. A failed transport can retry for a
  while; Escape cancels. The synthetic outage test limits retry duration only
  in its disposable fixture, not by weakening the production transport policy.

Other automatic classifiers, advisor/prewalk, completion probes, warm requests,
autolearn and the alternate native memory backend are disabled. This is a work
profile rather than a promise of every OpenCode plugin or local-model feature.
Native OTLP/marketplace defaults and trusted project discovery remain; inherited
`OTEL_*` endpoints may export telemetry. Required model IDs are checked, but
native OMP can still clamp efforts absent from the actual project catalog.
Optional native audio/model/runtime downloads are not certified by the source
build; do not run imperative installers to fill gaps without a Nix decision.

## Ownership and validation

OMP auth/session/cache data remains in OMP's native directories, not Pi/OpenCode.
The upstream HM module installs mode-600 **writable** `~/.omp/agent/config.yml`
because OMP locks/updates it; declared values are reapplied on activation. Native
MCP/model/agent/context/skill files are immutable declarations. Do not use OMP's
installer or config-writing commands to replace managed declarations.

The managed launcher refuses inherited Pi scope and unsupported named profiles
rather than silently opening another harness's state. An explicit alternative
agent directory must contain its own managed profile; it never falls back to the
real home. Runtime credentials are read only by the native credential wrapper.

```sh
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix build --no-link .#checks.x86_64-linux.omp-core \
  .#checks.x86_64-linux.omp-config .#checks.x86_64-linux.omp-wire
```

The native wire check executes the real source-built CLI in a Nix sandbox, with
fake project/catalog/gateway/proxy endpoints and the actual pure OpenCode option
resolver. It covers both APIs, default Sol
high, a real scout low task/read, refusal of an extra granted write, parent
continuation, separate state and an intentionally killed proxy with no direct
fallback. It is not proof of production WARP permissions or every native feature.
It includes actual launcher guards/version, a synthetic GitHub env-token command,
settings-driven extension loading and the model override. Service-helper tests
verify exec PID/lease/env ownership separately. The full real MCP stack, SOPS
fallback and interactive TUI are not end-to-end certified by these fixtures.
See the [complete review and dispositions](reviews/2026-10-23-omp-work-dispositions.md).
