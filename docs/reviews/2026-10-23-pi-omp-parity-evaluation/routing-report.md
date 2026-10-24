# Routing evaluation and working prototype

Legend: **[E]** executed/observed in this lab; **[C]** read in source, published metadata, or documentation; **[H]** recommendation/design inference, not a production deployment claim.

## Verdict

- [H] Use a small, dependency-free role extension on Pi 1.3.0's native virtual-model API. None of the ten surveyed packages provides OMP's role screen **and** request-reason routing **and** the required consumer integrations without additional glue or a competing routing stack.
- [E] The prototype is `model-roles/model-roles.ts`, with deterministic resolution in `model-roles/role-core.ts`. It loads in real Pi 1.3.0. Seven physical fixture models exercised normal turns, actual built-in compaction, retries, cooldown restoration, image attachments, CLI overrides, auxiliary consumers, role edits, and a custom role. All inference stayed on the lab loopback server.
- [E] **16/16 Node unit tests passed**, zero failures. The final run used Node 24.21.0 and `node --test /tmp/pi-lab/routing/model-roles/role-core.test.ts`.
- [H] Recommended new routing npm dependencies: **none**. Keep the repository's already-pinned `pi-subagents@0.80.0`; generate its model/thinking frontmatter from the role configuration. Do not add a second fallback/router package alongside this virtual router.
- [H] If choosing an off-the-shelf fallback-only alternative instead, `pi-model-fallback@0.5.7` is the best narrow option tested here. It does not replace the requested role system.

## Best artifacts

- [E] Clean role screen: `runs/models-ui-proved/models.png`.
- [E] Assigned retry fallback: `runs/models-ui-proved/models-edited.png`.
- [E] Cleared default, preserved fallback, and added custom RESEARCH role: `runs/models-ui-proved/models-custom.png`.
- [E] Narrow layout: `runs/compaction-proved/models-narrow.png`.
- [E] Physical routed-model footer: `runs/models-ui-proved/custom-route.png` and `runs/retry-cooldown/restored.png`.
- [E] Actual compaction: `runs/compaction-proved/compaction.png`.
- [E] Image routing: `runs/image-proved/vision.png`; the request contains one real `image_url` part and uses `vision`.
- [E] Alternatives: `depth/oips-working/cycle.png`, `depth/alexeiled-working/inspector.png`, `depth/fallback-working/recovered.png`, and the per-candidate `smokes/*/candidate.png` captures.
- [E] Machine-readable proof: `acceptance-evidence.json`, `pins.json`, `integrity-checks.json`, and each run's `requests.json` / `result.json`.

## Acceptance evidence

[E] Each row below was asserted against the fake server's recorded request bodies, not inferred from a notification or the fake answer text. Fixtures are physical models under provider `fixture`. `acceptance-evidence.json` records the exact reasoning-effort fields as well as model identities.

| Scenario | Observed wire-model sequence | Evidence |
|---|---|---|
| User turns and built-in `/compact` | `primary, primary, small, small` | `runs/compaction-proved/requests.json` |
| `--smol fixture/flag-smol:off` and built-in `/compact` | `primary, primary, flag-smol, flag-smol` | `runs/flag-proved/requests.json` |
| Primary HTTP 429, fallback, next turn during cooldown, restored primary | `primary, fallback, fallback, primary` | `runs/retry-cooldown/requests.json` |
| Real image user message | `vision`, one image part | `runs/image-proved/requests.json` |
| `--plan fixture/flag-smol:low`, then `/plan` | `flag-smol` | `runs/plan-flag/requests.json` |
| `--slow fixture/flag-smol:low`, then `/slow` | `flag-smol` | `runs/slow-flag/requests.json` |
| `/models` edit / add fallback / clear; `/role research ...`; `/use-role research` | `strong` | `runs/models-ui-proved/requests.json` and `agent/model-roles.user.json` |
| User turn, automatic title, `/advisor`, `/memory`, `/widget`, `/commit` | `primary, tiny, strong, tiny, tiny, tiny` | `runs/title-consumers/requests.json` |
| Tiny-title HTTP 429 and commit HTTP 429, both with explicit auxiliary-role fallback | `primary, tiny, fallback, tiny, fallback` | `runs/auxiliary-fallback/requests.json` |
| Existing fallback package, primary HTTP 429 | `primary, fallback` | `depth/fallback-working/requests.json` |
| Existing role package, documented key conflicts removed, Ctrl+P | `tiny` | `depth/oips-working/requests.json` |
| Existing adaptive-router profile with classification off | `primary` | `depth/alexeiled-working/requests.json` |

- [E] Pi made **two** small-model summary requests for the tested split-turn compaction; both were routed to the `smol` role. The title and auxiliary commands did not cause additional primary-agent turns.
- [E] The title-consumer run wrote real `worker.md` and `reviewer.md` agent definitions under `runs/title-consumers/agent/agents/`. Their model/thinking values reflect `task` and the reviewer override. That run also wrote the requested memory JSON and displayed the generated widget text.
- [E] A real `pi-subagents` child launch was **not** exercised. Frontmatter generation was exercised, its role/override precedence has unit coverage, and the package's launch contract was read.
- [E] Initial compaction runs correctly failed with “session too small”; longer synthetic history produced the successful compaction evidence above. The first image fixture was invalid and Pi omitted it before routing; a valid generated RGB PNG produced the successful image proof. Those failed attempts remain under `runs/normal-compaction`, `runs/flag-override`, and `runs/image-route`, and are not counted as proof.
- [E] An initial automated role-UI script sent the next command before the overlay relinquished keyboard ownership. The successful script adds an idle step after Escape; source interaction behavior did not require a workaround.
- [C] Pi clamps requested thinking to the physical model's supported levels. The generic fixture's requested `xhigh` is clamped to `high`; the wire evidence does not claim unsupported effort levels were served.

## Prototype design and behavior

### Loading and storage

- [C] `model-roles/package.json` is a private, dependency-free Pi package entry. Load its `model-roles.ts` extension by absolute path or the package directory. The host supplies the Pi and pi-tui imports; the extension has no non-peer npm dependencies or lifecycle scripts.
- [C] Immutable defaults come from `PI_MODEL_ROLES_CONFIG` or `--roles-config`; the value may be a JSON document or a JSON-file path. `model-roles/defaults.json` contains only fixture defaults. `model-roles/work-defaults.json` is an unexecuted proposed work profile using Pi's **`llm-platform`** provider ID, not OMP's `llmplatform`.
- [C] Writable edits go only to `<getAgentDir()>/model-roles.user.json`. Objects overlay defaults; role `null` explicitly clears the declared assignment and enables inheritance/auto-selection. Fallback arrays replace their defaults, including explicit empty arrays. CLI `--smol`, `--slow`, `--plan` and their `PI_*_MODEL` environment counterparts are process-only overrides and are not persisted.
- [C] The prototype uses same-directory atomic rename with mode-0600 temporary files. It does **not** provide multi-process locking or stale-edit conflict detection. The immutable defaults file is only read.
- [H] Production integration should use a writable overlay path distinct from Home Manager's managed files. Do not make that overlay a Nix-owned configuration file. If simultaneous Pi sessions edit roles, add bounded locking/conflict detection before adopting the prototype's persistence unchanged.

### Resolution and per-request routing

- [C] Selectors are exact `provider/model[:thinking]`, comma-separated availability alternatives, and recursive `@role[:thinking]` aliases. An alias cycle or exhausted availability alternatives fails explicitly. An explicit referring suffix wins over the alias target's suffix.
- [C] Supported thinking suffixes are `off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, and `inherit`. `auto` is intentionally rejected: this prototype does not pretend to implement OMP's judgment-based auto-thinking.
- [C] `roles/auto` is a real registered virtual model. Normal user requests use `default`; `/plan` selects plan routing and a read-only tool allowlist; `/slow` selects slow routing; a latest-user-message `ultrathink` keyword selects slow for that turn; `/build` restores default routing and the previous tool set. A tool-call guard blocks non-read tools while the prototype's plan mode is active.
- [C] Image-bearing user requests select `vision`; if the chosen physical route cannot accept images, the router errors rather than silently dropping them. This checks images present in the routed request, including retained historical image parts.
- [C] Generic `direct` calls through `roles/auto`, including built-in compaction, select `smol`. The integrated title generator explicitly invokes the `tiny` consumer. An unrelated extension that calls a physical model directly cannot be transparently rerouted by this extension.
- [C] `continuation` stays on the previous successful physical model and thinking level. Retried requests use `request.failed`; the role is carried in Pi's branch-persisted router state. The native footer records/displays the physical dispatch separately from the selected virtual model.
- [C] Unassigned role inheritance is explicit: `smol/slow -> default`, `plan/advisor -> slow`, `commit/tiny/widget -> smol`, `memory -> tiny`, `task/vision -> default`. A cleared custom role uses `default`. An unassigned default uses the first available physical model; the prototype does not copy OMP's extensive built-in model-priority lists.

### Retry fallback

- [C] Fallback is disabled with empty chains by default, matching the requested work-profile posture. A chain is not inferred from comma-separated primary alternatives.
- [C] Chain precedence is exact `provider/model`, then `provider/*`, then active role, then `default`. Explicit `[]` stops inheritance. A `provider/*` chain entry keeps the failing model ID and swaps provider. Bare declared fallback selectors inherit the failing thinking level; a suffix replaces it.
- [C] HTTP 429 / rate limits, overloads, quota exhaustion, context-length overflow, and relevant 5xx errors are eligible. Authentication errors and arbitrary non-retryable failures do not disclose the conversation to another provider.
- [C] Router state carries failed-model cooldown deadlines and visited models. Subsequent user turns use a configured healthy fallback until the fixed cooldown expires, then restore the primary. Exhausted chains fail without ping-pong. A fallback model's own exact/provider chain may be consulted on its subsequent failure.
- [C] Title, commit, advisor, memory, and widget helpers also resolve declared fallback chains, but only when `modelFallback` is explicitly enabled. Auxiliary requests retain their local cooldown state in memory. They do not depend on the parent agent-loop retry machinery.
- [C] The prototype does not implement OMP's `fallbackOn` policy variants, prefixed wildcard namespaces, Retry-After/quota-reset parsing, usage-aware account routing, context-promotion configuration, or the `never` revert policy. It uses the configured fixed `cooldownMs` (60 seconds when unspecified).

### Role UI and consumers

- [E] `/models` provides colored role dots/names, assignment text, an all-model/provider-count sidebar, a real model picker followed by a thinking picker, Enter assignment, `f` addition of a retry fallback, `d` clearing, and `+ New role…`. Editing an alias/non-interactive exact selector works through `/role <name> <selector>`; `/role name -` clears it. Adding a fallback is an explicit opt-in that enables model fallback in the writable overlay.
- [C] The sidebar is informational, not a provider-filter navigation control. No fake model-kind tab is shipped. Only chat consumers and custom roles are exposed.
- [C] `/use-role <name>` runs subsequent conversation turns on any configured/custom role. `Ctrl+Shift+U` cycles `cycleOrder` (default `smol, default, slow`); **native Ctrl+P remains scoped-model cycling**. The shortcut is registered but its terminal key encoding was not separately driven in the lab.
- [C] `/commit` drafts a message from explicit input or the bounded session transcript; it never invokes Git or creates a commit. `/advisor` makes a real independent review call. `/memory` writes real generated notes to the writable agent directory. `/widget` makes a real model call and shows the generated short status. These are real consumers, not stored-but-unused role names.
- [C] These scoped commands are **not** OMP's background advisor watchdog, full memory consolidation/retrieval, or per-background-job live-widget engine. They are a concrete way Pi can consume those allowed roles without placeholder entries. The distinction must remain visible in user-facing integration docs.
- [C] Mode names are stored as custom session entries and restored at session start. The prototype does not separately resynchronize its command-mode variable on arbitrary `/tree` branch changes. The per-request virtual-router state itself is branch-aware because Pi persists it.

### Subagents and Nix cutover

- [C] The repository currently pins `pi-subagents@0.80.0`, not the registry's newer 0.81.0. Its documented precedence is per-run model override, provider-scoped role override, ordinary agent override, agent frontmatter, subagent default, parent model. Exact provider/model IDs avoid ambiguity. The package resolves **one** model per launch and does not supply an OMP-style model fallback chain.
- [C] `agentFrontmatter()` resolves `task.agentModelOverrides[name] ?? @task` and writes distinct `model:` and `thinking:` frontmatter, preserving explicitly supplied agent descriptions, prompts, and tool allowlists. `/role-agents` exercised this mapping in the lab. It is an explicit generation command, not a background writer of Nix-managed files.
- [H] For final Nix integration, resolve declared role defaults into the existing `roleFile` generator in `modules/home-manager/pi-routing.nix`; keep the current required-child-extension, MCP, tool, and inheritance policy. Remove the old primary `routing.ts` command/title registration when enabling this extension: loading both would duplicate `/plan`, `/build`, and title generation.
- [H] Writable UI changes to task roles do not automatically rewrite immutable Nix frontmatter. True live task-role edits require a pre-launch adapter to the subagent API, or writable agent definitions in an explicitly separate generated namespace; that is additional integration, not a capability proved here. Do not write through Home Manager's agent-file symlinks.
- [H] Likewise, physical model selection through Pi's native `/model` intentionally bypasses `roles/auto`. Set Pi's declared default to `roles/auto` when adopting the router. Do not select a physical model and promise that an extension can intercept every third-party physical inference call.

## Survey: coverage, quality, security

[C] All ten top-level candidates below declare MIT licenses and no `bin`. No top-level candidate tarball contained `.node`, `.so`, or `.dylib` native modules in the static inventory. No top-level non-peer dependency declares a native addon. The host's own image-processing WASM is not a new package dependency. This is a scoped static review, not a blanket assurance about all transitives or future versions.

[E] Registry tarballs were fetched into `pkgs/`, extracted without executing lifecycle scripts, and their SHA-512 bytes were checked against metadata. Full exact dependency maps, all scripts, `bin`, license, unpacked size, and integrity are recorded in each `pkgs/<slug>/audit.json`; full registry responses are in `metadata.json`. `static-audit.json` contains file/line evidence for filesystem, subprocess, and network surfaces. Isolated dependency installation used `--ignore-scripts --no-audit --no-fund` and a lab-local npm cache. No `pi install` was run.

### @d3ara1n/pi-model-roles@2.0.0

- [C] Small, zero-dependency role API with `/roles` inspection and `list_models`. Its defaults are `default/heavy/fast/utility` with nullable models, not OMP's workload routing. Other extensions must explicitly consume the shared API. No role editing UI, reason-based virtual routing, fallback-chain engine, CLI role flags, or automatic compaction interception.
- [E] Loads on Pi 1.3.0; `/roles` resolved all four defaults to the local fixture. Evidence: `smokes/d3ara1n__pi-model-roles`.
- [C] Configuration reads the agent/project settings; model calls use Pi's configured registry. No direct network URL, subprocess, or filesystem-write hit was found in its shipped runtime source. Consumers can still make explicitly requested provider calls.
- [H] Good small library if buying into its consumer ecosystem; not useful enough to add beneath the native virtual router.

### @oipsanthony/pi-model-roles@0.2.0

- [C] Closest small selector/alias/cycle implementation: `provider/model:thinking`, `@role:thinking`, `cycleOrder`, transient colored role rail, and deferred default-role resolution. No OMP `/models` role editor or per-workload interception.
- [E] Default Pi bindings cause the Ctrl+P extension shortcut to be skipped. The documented rebindings worked after also moving the built-in provider-display toggle and session-path toggle: the depth proof selected `tiny` and sent its actual request to `tiny`.
- [C] **Nix concern:** startup code can rewrite user or trusted-project `settings.json` to move this package before a powerline package. It has no network or subprocess implementation, but it is not read-only at startup. Roles are read from a separate JSON file.
- [H] Reuse selector/cycle design ideas rather than shipping unmodified; preserve native Ctrl+P and use Ctrl+Shift+U in our extension.

### @wuyaos/pi-model-roles@1.1.0

- [C] A fork of the small shared-role API with model-facing `use_role`/`use_model` tools. The tool description embeds the author's named models and workloads. Its convenience completion methods import pi-ai's compatibility transport rather than simply using the host registry methods throughout.
- [E] `/roles` loads and renders on Pi 1.3.0: `smokes/wuyaos__pi-model-roles`.
- [C] No direct network, subprocess, or write hit was found in its own runtime source; the compatibility API performs the requested model inference. Its shared global API key overlaps the d3ara1n library; loading both is not an appropriate integration strategy.
- [H] Less maintainable fit than the original library or our explicit virtual-router core; do not add it.

### pi-model-fallback@0.5.7

- [C] Narrow provider/exact-model failure rules; status/reason matching; persisted cooldown state with `proper-lockfile`; atomic merges; cancellation and non-replay recovery; cascading fallback rules. This is a failure-rule system rather than an OMP role table/alias resolver.
- [E] `/model-fallback:status` loads. A real scripted HTTP 429 on `primary` continued the same conversation on `fallback`: `depth/fallback-working`.
- [C] Writes config/state under the agent or project `.pi` directory, with shared locking. Its configuration tool can save settings. No subprocess or independent network destination found; Pi's normal configured providers receive inference. Switching provider sends existing conversation context to the fallback provider.
- [C] Default configuration enables a Z.ai-to-DeepSeek rule. Its stock 429 cooldown can be 72 hours. Neither default matches the user's requested empty/disabled work profile.
- [H] Best fallback-only package alternative, provided defaults are explicitly replaced. Do not layer it onto `roles/auto`: it changes the active physical model and can bypass our role router.

### @henryqw/pi-task-models@9.1.4

- [C] Well-defined task-profile control plane with explicit consumer registration, `fast/balanced/frontier/fav` profiles, primary/fallback routes, scoped-model/thinking validation, presets, and careful config-error handling. Its profiles are deliberately fixed, not arbitrary OMP role names; consumers must adopt its API.
- [E] `/task-models` opens its real profile UI and warns clearly about missing config: `smokes/henryqw__pi-task-models`.
- [C] Filesystem changes delegate to `@henryqw/pi-config-store`; that package uses private directories/files, atomic writes and `proper-lockfile`. No direct network or subprocess behavior found in the task-profile package. The package does not itself route the parent's normal or compaction requests.
- [H] Stronger persistence engineering than the throwaway prototype, but the API/profile mismatch and extra dependencies are unnecessary for this integration.

### @getpipher/vision@0.5.3

- [C] Specialized modality-aware `describe_image`, paste handling, per-image delegation, retry/fallback, local cache/audit records, local-only mode, and a `/vision` settings UI. It is not a general role router.
- [E] `/vision show` loads on Pi 1.3.0 with no model inference during the smoke: `smokes/getpipher__vision`.
- [C] Its delegate sends a raw `fetch()` to the configured model base URL's `/chat/completions`, rather than using the model's arbitrary Pi API transport. This is a material limitation for Responses/Anthropic/custom-provider auth/transport policies. Compression uses Pi's image utility; no new native image module is declared. It writes config, cache, and a default-enabled local delegation audit log; no subprocess implementation found.
- [C] Default local-only mode is false and vision autodetection is enabled, with documented cloud preferences. Explicitly pin a model and disable autodetection before considering it in the immutable work profile.
- [H] Not needed for image attachment routing via `roles/auto`. Consider separately only if its image/paste tools are desired and its raw transport is acceptable.

### pi-advisor-flow@0.14.2

- [C] Rich second-opinion workflow, manual and automatic loop gates, model configuration, outcome stats, optional context/scout processing. This is a real potential advisor consumer, not a replacement for general role routing.
- [E] Shipped built JS loads without lifecycle scripts; `/advisor-stats` works: `smokes/pi-advisor-flow`.
- [C] `preinstall` runs a Bun-version checker and `prepare` runs Husky; neither may execute in the Nix build. It writes advisor settings/outcome state. It uses `git` through `execFileSync` for repository/attachment inspection (shell disabled), and its model calls disclose eligible bounded conversation/attachments to explicitly configured model providers.
- [C] No separate telemetry endpoint was found in the reviewed runtime source. That does not make its configured secondary inference or optional scout calls free of disclosure/cost.
- [H] Optional future advisor watchdog integration only after explicit configuration and tool/privacy review; not needed for the base role system.

### @pi-unipi/fusion@2.20.5

- [C] A lead-plus-persistent-sidekick workflow with its own picker, preset state, child Pi spawning, and `~/.unipi` state/config ownership. Only a pair, not the required workload roles. Non-peer dependencies pull in UniPi core and subagents.
- [C] Its declared Pi peer range is `^0.84.0`, which excludes Pi 1.3.0. Source writes presets/prompt/session state and spawns child Pi processes.
- [E] Disqualified before installation/runtime execution for incompatible declared host range and competing side-agent/config architecture. Metadata and source were inspected; no successful Pi 1.3.0 smoke is claimed.

### pi-router@0.5.9

- [C] A substantial custom-provider relay for channels, circuits, sticky routing, model failover, probes, logs, and configuration wizard. It is not the OMP workload-role UI or native `request.reason` router.
- [E] It loads and opens its real menu on Pi 1.3.0: `depth/pi-router/menu.png`. No inference ran during that menu smoke.
- [C] It reads `models.json` and `auth.json` for channel discovery, writes router config/state/logs and a generated README, and defaults local auto-sync on. Paid health probes are opt-in/off by default; optional summary transfers make extra configured model calls. No subprocess implementation found in its runtime source inventory.
- [H] Too broad and configuration-heavy for this task. Avoid an additional credential/channel state layer when Pi's virtual model API already supplies the necessary dispatch hook.

### @alexeiled/pi-model-router@0.16.0

- [C] Best substantial alternative for adaptive tier/activity routing: profiles, explicit generation fallbacks, classifier consent, between-request adaptation, a five-tab native inspector, observed usage, and session-only editing. Uses a custom provider and Pi registry/classifier APIs, not the OMP role model.
- [E] `/router profile lab` selected a real local profile and the generation request used `primary`; `/router` opened the inspector: `depth/alexeiled-working`. An earlier `/router lab` command was rejected with a helpful grammar error, not counted as a routed-profile proof.
- [C] No npm runtime dependencies. It persists selected profile metadata in the agent directory and router state in session entries; logging is opt-in. Classifier advice requires explicit configuration/approval and can disclose bounded recent text. No independent subprocess or raw provider-fetch destination found in its runtime inventory.
- [H] Good independent product, but replacing OMP roles with tiers is the wrong requirement. Do not combine its `router` provider with pi-router or add it just to obtain a role screen.

## Exact npm pin / immutable-build inventory

[C] All entries below are top-level metadata pins. `dependencies` means non-peer runtime dependencies. Lifecycle column explicitly covers install/postinstall/prepare (and preinstall where present). Complete scripts, including development/release scripts that are not executed, remain in the cited audit JSON.

| Package | Unpacked bytes | Non-peer dependencies | Install lifecycle | Native / bin / license |
|---|---:|---|---|---|
| `@d3ara1n/pi-model-roles@2.0.0` | 38,513 | `{}` | none | none / none / MIT |
| `@oipsanthony/pi-model-roles@0.2.0` | 34,929 | none | none | none / none / MIT |
| `@wuyaos/pi-model-roles@1.1.0` | 34,963 | `{}` | none | none / none / MIT |
| `pi-model-fallback@0.5.7` | 87,702 | `proper-lockfile: 4.1.2` | none | none / none / MIT |
| `@henryqw/pi-task-models@9.1.4` | 124,374 | `@henryqw/pi-config-store: ^4.0.0` | none (`prepack` builds; not an install hook) | none / none / MIT |
| `@getpipher/vision@0.5.3` | 180,560 | none | none | none / none / MIT |
| `pi-advisor-flow@0.14.2` | 1,027,305 | none | `preinstall: node scripts/check-bun-version.mjs`; `prepare: husky`; no install/postinstall | none / none / MIT |
| `@pi-unipi/fusion@2.20.5` | 133,891 | `@pi-unipi/core: 2.20.5`, `@pi-unipi/subagents: 2.20.5` | none | none / none / MIT |
| `pi-router@0.5.9` | 1,173,242 | `{}` | none | none / none / MIT |
| `@alexeiled/pi-model-router@0.16.0` | 442,394 | none | none | none / none / MIT |

[C] Exact `dist.integrity` values:

- `@d3ara1n/pi-model-roles@2.0.0`: `sha512-2TBKSuv9jdrIaXWlfCu9fs0Lw8sz2tEdrqpOY/fetcdBogPg5CCO7YAfJukVkj5pbZzLi4xO9yKoKiQkbGmlOg==`
- `@oipsanthony/pi-model-roles@0.2.0`: `sha512-/7I8gD6J8lKfOzggsJx0BRPcy3OUx9W4wZrBVir9V8gFVvx/SsooO/qytzIvA97sEMzPuDoZoouvnBcwLzsVEA==`
- `@wuyaos/pi-model-roles@1.1.0`: `sha512-PO6Djr4nrX0OLRR1dDMdE2thdK1364/V+8mMCyPYIlI5OCy2IN2+vr5GpT8bLlHDWvvq3C/Nst+ItRXqiqvS5w==`
- `pi-model-fallback@0.5.7`: `sha512-bt6E/iOwqQSWUvmDy0PmWr0kKtQrCpwKkeKtNiWtbrk/UDev7UC6rTKYP2om9pMC2wZ8EPopycTVtmg6ebutZA==`
- `@henryqw/pi-task-models@9.1.4`: `sha512-aEeJ6mhFv8++UZeluXQQPNukuTx1Ic2aPKh2+4UHM6oj7T5d0Ego7XwLa+baLt0ET78/ioXS3xE2QUA81+1xvQ==`
- `@getpipher/vision@0.5.3`: `sha512-nInSwMc+XSylMWAcK5LhoHi0N6zxA4R2dy99byDGph49kHL0Tcym7qj41zT52m9oi2lIQsTglBMnhXb5vCTtiw==`
- `pi-advisor-flow@0.14.2`: `sha512-MQScgzKF1IMiNi7+vW6CzMPOuZiQ2fQbnd0fl/VzW0KFqEXUajsyhM/l1tWO8+70OPwsvvwGVIE9eK+/j2/Odw==`
- `@pi-unipi/fusion@2.20.5`: `sha512-GADa5vSmwB/xdqR5KAdsLjhfjY6fDTr43U/KVj9nIOFrFKNchU6QY55PHDlVuDs0IZO7aCmbdeI7pe7kxLa/5w==`
- `pi-router@0.5.9`: `sha512-6CpMkkk5rFLZQ54YQ+UcDSZSLqiPL2Dy/Rj0d67gphGSHJY/TQkPThr/icdUcOIA8PWNfyBnTHzIpmwDiAm2nQ==`
- `@alexeiled/pi-model-router@0.16.0`: `sha512-QzuNS9pklxjyPbuShBfo3+IbaKF7k1k/nanH2DTbCKa/gGzn0nEb6PuCOomqEDfGJany7X38vIz0ZE0AUMT+Qw==`

[C] Supporting pins, not additional base-router dependencies:

- Repository carry-forward `pi-subagents@0.80.0`: `sha512-7tTRbVnCuhhC13S3RmxSUnYzF98za+NEqnzVJhsDdNp242CMS71Y3pigkT+lZyVHhzhyxJLfwYiss9vqtwm4dg==`; unpacked 6,832,883 bytes; dependencies `@js-temporal/polyfill: 0.5.1`, `acorn: 8.18.0`, `jiti: 2.7.0`, `undici: 8.10.2`, `yaml: 2.8.3`; no lifecycle scripts; bin `pi-subagents -> install.mjs`; MIT. The installer invokes Git and can clone the repository; **do not execute the bin**. Runtime child spawning/state writes are inherent to the existing audited subagent integration, not newly adopted here.
- `@henryqw/pi-config-store@4.0.0`: `sha512-vQDL2UqgpsesRKmVSTe6IJwa9ROxAUdj9W6FMeceGVkrrf1Cthax2yvS8JTk0SWyxqcCuGSdUBt+bmjooLmQDw==`; 50,090 bytes; dependency `proper-lockfile: ^4.1.2`; no install/postinstall/prepare; no bin/native module; MIT.
- `proper-lockfile@4.1.2`: `sha512-TjNPblN4BwAWMXU8s9AEz4JmQxnD1NNL7bNOY/AKUzyamc379FWASUhc/K1pL2noVb+XmZKLL68cjzLsiOAMaA==`; 29,875 bytes; dependencies `graceful-fs: ^4.2.4`, `retry: ^0.12.0`, `signal-exit: ^3.0.2`; no install/postinstall/prepare; no bin/native module; MIT. Its npm release script exists in metadata but was not run.
- [H] Any dependency-bearing alternative needs a complete locked transitive closure, peer resolution against the host, disabled lifecycle scripts, and fixed tarball hashes. `pkgs/package-lock.json` is lab evidence, not a recommendation to vendor duplicate Pi host packages: npm resolved extra peers during the isolated audit install.

## OMP parity boundary: impossible through this router alone versus extra work

| Feature | Boundary |
|---|---|
| Native global path-scoped `enabledModels` | [C] `ctx.scopedModels` is a read-only snapshot; the extension API has no setter for the native scope. [H] Startup wrappers can derive `--models` per path, or our router/picker can enforce a path policy for its own routes. That does not globally rewrite every native picker/physical selection in the running session. |
| Same-provider round-robin credentials/accounts | [C] A virtual route returns only model/thinking/state, not an account. Pi's public registry resolves provider auth; it exposes no OMP account-policy scheduler. [H] An explicitly configured provider alias or external credential broker/custom provider can implement this, but that is a separate auth design. |
| OMP advisor watching every turn / steering | [C] Pi has lifecycle events, auxiliary inference, and steering/follow-up APIs; there is no built-in OMP advisor-role consumer. [H] An extension such as the reviewed advisor workflow can implement a real watchdog, with explicit disclosure/cost/cancellation policy. Not intrinsically impossible, not supplied by the small router. |
| Judge and automatic thinking | [C] Pi 1.3.0 **does have** classifier APIs, including `modelRegistry.classify()`. It is incorrect to call classification impossible. [H] OMP's judgment schema, auto-thinking policy and workload wiring require a separate real consumer. The prototype rejects `:auto` rather than shipping a fake judge role. |
| OMP background-job widget role | [C] Pi offers UI widgets, but not OMP's background-job widget-spec consumer. [H] A job-owning extension can call the widget role and render live state. The prototype's real `/widget` command is only an on-demand status consumer. |
| Automatic memory consolidation/retrieval | [C] Not a core Pi workload role. [H] Add a real memory extension/consumer if wanted; the prototype only generates and stores explicitly requested notes. |
| Image/web/speech/dictation/judge model-kind tabs | [C] These OMP role consumers are not shipped by the prototype. Pi has image/classifier registry APIs, but not the same full runner catalog/consumer set. [H] Add only actual tools/consumers, not inert role rows. |
| Intercept every extension's title/side-model call | [C] Native virtual routing only applies when the call selects that virtual model. Direct calls selecting a physical model bypass it. [H] Migrate those callers to the shared consumer resolver; do not claim global monkey-patching parity. |
| Exact OMP fallback/account/usage policy | [C] The prototype covers declared model chains, failures and fixed cooldown restoration, not usage reserve/account rotation or all OMP recovery-order details. [H] Public provider-response hooks can supply HTTP timing metadata for more complete cooldown parsing; OMP account policy still needs a separate auth layer. |
| OMP presets, scoped settings layers, full fuzzy/catalog priorities | [C] Not implemented by the prototype. [H] Technically reproducible in extension-owned configuration/UI, but not necessary to prove the requested exact-selector role system. |

## Sources and reproducibility

- [C] OMP references read: the **whole** `omp://models.md` including lines 706–1217, `omp://settings.md` role/fallback sections, `omp://keybindings.md` role cycling, `omp://cli-reference.md` role flags, and `ref/omp-models-roles.png`.
- [C] Pi references read from the pinned 1.3.0 installation: `docs/virtual-models.md`, relevant extension/tui examples and declarations, model registry and compaction implementation, plus the repository's read-only `routing.ts`, `pi-routing.nix`, `pi-subagents.nix`, and routing documentation. The live OMP config/auth files were not read; the assignment supplied the relevant role values.
- [E] Scenario inputs are under `scenarios/`; reproduction drivers are `run-smokes.py`, `run-prototype.py`, `run-depth.py`, and `run-final-scenarios.py`. The successful direct image/auxiliary scenarios can also be run with the shared `/tmp/pi-lab/lab.py` driver. All generated paths and artifacts stay inside this routing directory.
- [E] No real provider credentials, real LLM endpoints, `pi install`, Git writes, Home Manager activation, or repository edits were used.
- [E] Pi loading and the recorded runtime scenarios were exercised; a separate TypeScript static typecheck/linter was not run. This is a throwaway working prototype and design report, not a production Nix integration claim.
