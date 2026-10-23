# LSP evaluation for Pi 1.3.0

## Verdict

- [H] Recommend **one package: `@ian-pascoe/pi-lsp@0.15.1`, with the narrow push-diagnostics eligibility patch and a thin composable status adapter in this lab**. Do not enable its unpatched npm release and claim automatic diagnostics work with the requested servers.
- [E] Recommended package integrity: `sha512-2SMfMyYFuMXjKS/2dHslNKKtq9FsATP9TaVtz3dRCdkRubsJ5JXOImCEXbiP+8ZNx1o+aq5Vh6/7MYIWpCoEJw==`. The downloaded tarball's SHA-512 was checked against registry metadata.
- [E] The patched prototype delivered real Go and TypeScript errors inside the edit tool results in the **immediately following model request**, returned real definition/references/hover/rename-preview/symbol/code-action results, and displayed both server names in the footer.
- [E] Its existing version-aware client also passed a delayed-real-gopls experiment that made `@piex-dev/lsp` and `pi-lsp-extension` emit obsolete errors after the file was already repaired.
- [H] This is a research recommendation, not a claim of production Nix qualification: Nix/Python servers, applied refactors, and the final packaged dependency closure still need integration checks.

## Deliverable map

- [E] Best full screenshot: [`runs/ian-patched-ready/complete.png`](runs/ian-patched-ready/complete.png); footer reads `LSP gopls ● · typescript ●`.
- [E] Strongest freshness screenshot: [`runs/ian-patched-delayed/complete.png`](runs/ian-patched-delayed/complete.png), with the error panel above the successful repair and the server footer below.
- [E] Prototype package: [`ian-patched/`](ian-patched/); patch: [`ian-push-diagnostics.patch`](ian-push-diagnostics.patch); adapter: [`ian-patched-status-bridge.ts`](ian-patched-status-bridge.ts).
- [E] Precise proposed global settings: [`recommended-settings.json`](recommended-settings.json). Executed Go/TS settings, including recorder commands and the exact tested timeouts, are in [`runs/ian-patched-ready/agent/settings.json`](runs/ian-patched-ready/agent/settings.json).
- [E] Machine-readable evidence: [`evidence.json`](evidence.json). Every run's `requests.json`, `rpc.jsonl`, `events.jsonl`, `guard.jsonl`, terminal text, raw ANSI and screenshots are retained under [`runs/`](runs/).
- [E] **All 15 candidate pins, dist.integrity values, non-peer dependencies, full scripts, bin, licenses, unpacked sizes and peer requirements** are recorded without abbreviation in [`metadata.json`](metadata.json). Each `candidates/<slug>/` also contains the registry response, verified tarball, unpacked source, metadata summary and code-audit hits.
- [E] Native/WASM and bundled lifecycle inventory: [`native-inventory.json`](native-inventory.json). Executed installation lock: [`runtime/package-lock.json`](runtime/package-lock.json); installation used `--ignore-scripts --legacy-peer-deps --omit=dev --no-audit --no-fund` in an isolated lab home/cache.

## Method and limits

- [E] All writes, throwaway homes, projects, package installations, logs and prototypes stayed under `/tmp/pi-lab/lsp/`. Repository/worktree material was read-only. No real LLM endpoint or credential was used: real Pi 1.3.0 ran against the lab's loopback scripted model.
- [E] Real servers were Nixpkgs `gopls 0.24.0`, Go `1.26.9`, `typescript-language-server 6.0.2`, TypeScript **5.9.3**, and Node `24.21.0`.
- [C] The current `nixpkgs#typescript` resolved to 7.0.2. Classic typescript-language-server requires `tsserver.js`; the tested and proposed pairing uses `typescript_5`, not an interchangeable TypeScript 7 install. OMP's documented native-TS7 backend is a separate choice.
- [E] `rpc-proxy.mjs` recorded the actual servers' JSON-RPC frames and timestamps. For induced-latency runs only, it delayed the servers' own `publishDiagnostics` frames by 9000 ms; it did not invent diagnostics, change content, or replace a real server.
- [E] `observe.ts` recorded extension-handler durations, tool results and project trust. Node subprocess and external network guards were active for corrected runs. No external socket/fetch attempt was observed in the recommended-package runs.
- [E] A kernel-level network namespace was unavailable: `unshare -n true` failed with `Operation not permitted`. The Node guard is not proof against arbitrary native subprocess networking; Go used `GOPROXY=off`, `GOSUMDB=off`, `GOTOOLCHAIN=local`, `GOTELEMETRY=off` and isolated caches.
- [E] Initial `ian`/`piex` runs intentionally remain as failed-launch evidence: the recorder first supplied the removed `--tsserver-path` CLI flag. Corrected runs use TypeScript initialization options or `NODE_PATH`; those launch failures were harness configuration errors, not plugin defects.
- [E] Initial `lens-smoke` and `ian-patched` runs sent Enter before the editor was reliably ready and made zero model requests. Readiness-synchronized runs subsequently succeeded. Those two timeouts are not compatibility failures.
- [C] Static screening stopped candidates as soon as their documented/code surface failed a required capability. No runtime smoke is claimed for those disqualified candidates.

## Required OMP parity

- [C] OMP's `omp://lsp-config.md` documents PATH/local-binary discovery, root markers, JSON/YAML configuration and lazy servers. `omp://tools/lsp.md` documents navigation, semantic rename, code actions, version-aware push/pull diagnostics, explicit failures and status. `omp://tools/edit.md` documents edit/write LSP writethrough and optional format-on-write.
- [C] Pi's public `tool_result` event can return modified `content`; `context` can transform model messages; `sendMessage` injects a separate message. These are different contracts, not equivalent UI notifications.
- [H] The smallest matching integration is synchronous post-mutation `tool_result` enrichment plus persistent server clients, with `setStatus` contributions consumed by the chosen custom footer. Automatic formatting is independent and should stay off unless separately requested.

## Executed acceptance results

| Candidate/run | Next model request after broken Go / TS edit | Navigation | Persistent footer | Timing |
|---|---|---|---|---|
| [E] Stock ian, `ian-fixed-launch` | **Neither** error was appended | Definition, references, hover, rename preview, symbols, code-action listing succeeded | Only via lab adapter | Its pull-capability gate excludes both tested push-only servers |
| [E] Patched ian, `ian-patched-ready` | **Both** error diagnostics are inside their edit tool results | All six requested categories returned real results | `setStatus("lsp", …)` bridge; both server names visible | Go cold pre-edit work 361 ms, post-edit 5 ms; TS 653 ms pre-edit + 369 ms post-edit |
| [E] Piex, `piex-fixed-launch` | **Both** errors appended to edit tool results | Definition, references, hover, rename preview and symbols succeeded; code-action tool returned no actions at the selected point | None upstream | Go post-edit 948 ms; TS 1435 ms |
| [E] pi-lsp-extension, `extension-cold` | **Neither** error appended | Explicit navigation subsequently started servers | Native `lsp` status entry | Cold edit hooks 7/4 ms: no server startup, therefore no diagnostics |
| [E] pi-lsp-extension, `extension-warm` | Both appended after configured eager startup | Explicit navigation tools exercised | Native `lsp` status entry | Every mutation waits a fixed ~1501–1502 ms |
| [E] Lens, `lens-trusted` | Both appended to edit tool results; additional incomplete-auxiliary-check warnings | Navigation not runtime-tested in this lab | Native `pi-lens-lsp` entry and diagnostic widget | Go post-edit 3597 ms; TS 837 ms |
| [E] Lens, `lens-ready`, untrusted | No LSP processes; TS says unavailable; Go tool result said “Go clean” despite the introduced type error | Not exercised | `LSP Inactive` | Untrusted-project LSP startup is intentionally blocked |

- [E] In `ian-patched-ready/requests.json`, request **3** includes the Go type error in `lab-2-0`'s tool content; request **4** includes the TS2322 error in `lab-3-0`'s tool content. They are not merely an injected message, footer badge or screenshot.
- [E] Requests following the Go `write` repair and TS `edit` repair contain explicit clean diagnostic outcomes. This tests both write and edit integration.
- [E] Patched ian's real Go definition resolves the call on line 8 to line 3; TS references include the declaration and call site; hover gives the function signature; rename produces a two-location Workspace Edit Preview. Document symbols include `count` and `greet`.
- [E] The selected TS range returned three command-only refactor actions through ian's `lsp_code_actions`. [C] The plugin honestly labels those command-only actions “cannot be applied”; it applies edit-bearing actions/previews through `lsp_apply` instead of executing arbitrary server commands.
- [E] Server spawn → first actual publish latency in the final patched run: **gopls 318 ms**, **TypeScript 615 ms**. These first publishes can be the pre-edit clean baseline. For Lens's trusted/read-warmed run the corresponding measurements were 163 ms and 1466 ms. These are single fixture observations, not benchmark percentiles.

### Cold/stale diagnostic stress results

| Run with actual diagnostic frames delayed 9 s | Broken-file NEXT request | Repaired-file NEXT request |
|---|---|---|
| [E] `piex-delayed` | Misses error; hook returns after 6078 ms | **Wrongly appends the old error** after the successful write; hook 3857 ms |
| [E] `extension-warm-delayed` | Misses error after fixed 1501 ms wait | **Wrongly appends the old error** after the successful write |
| [E] `ian-patched-delayed` | Correct current-version error; post-edit wait 9008 ms | Correct explicit clean result; post-write wait 9005 ms |

- [E] All three delayed-run final `main.go` files contain `var value int = 42`. Obsolete reported errors refer to the earlier `"wrong"` value. Raw model requests and RPC frames are retained; see `evidence.json` for first appearance by request.
- [C] Piex discards the publish `version` field (`src/lsp.ts:475-481`), retains old diagnostics while clearing only arrival flags (`:232-235`), and returns its cached diagnostics even when waiting times out (`:585-604`). Its collector ignores `timedOut` and swallows server errors (`:1072-1097`).
- [C] pi-lsp-extension reads the cache after a fixed delay without a version freshness predicate (`dist/index.js:4712-4724`). Its cold hook explicitly refuses startup when there is no running client.
- [C] Ian already has version-aware push/pull handling, rejects superseded versions, and distinguishes timeout from clean (`src/lsp-server-client.ts:702-807`). The bad eligibility gate was outside that client.

## Why the narrow ian patch is needed

- [C] Stock `src/pi-lsp-extension.ts:241-247` routes post-edit diagnostics only when `hasCapability(textDocument/diagnostic)` is true. `lsp-server-client.ts:553-554` interprets that as a document-pull registration, not the ability to publish diagnostics.
- [E] Neither real gopls 0.24.0 nor typescript-language-server 6.0.2 advertised a document-pull provider in these sessions. Both published real diagnostics and supported navigation; the stock middleware nevertheless skipped them silently.
- [C] Its explicit diagnostic tool already uses `isSupportedBy: () => true` (`src/lsp-tool.ts:481-484`). The patch reuses that convention for post-edit diagnostics and removes the same pull-only exclusion from the dependent-file scan. It does not replace the transport, introduce retries or add fallback compiler commands.
- [E] The patched package was exercised through real Pi, both real servers, next-request inspection and the delayed-real-gopls probe. No production repository file was patched.
- [H] Carry this as a named Nix source patch, submit upstream, and remove it when an upstream release fixes push-only eligibility. Do not install both the stock extension and the adapter: the adapter registers the extension itself.
- [C] Making all configured servers eligible also means a deliberately configured formatting-only server would now yield a diagnostic timeout instead of disappearing. The proposed configuration contains only diagnostics-capable servers; no formatter-only server is added.

## Exact proposed integration

### Package and dependency pinning

- [H] Fetch the verified npm tarball for `@ian-pascoe/pi-lsp@0.15.1`, apply `ian-push-diagnostics.patch` during the Nix build, and vendor an immutable npm dependency closure with lifecycle scripts disabled. The package has no install/postinstall/prepare hook, no native module, and no server installer.
- [E] Executed resolution: `@ian-pascoe/pi-utils 0.10.0`, `cross-spawn 7.0.6`, `vscode-languageserver-protocol 3.18.5`, `vscode-languageserver-types 3.18.5`, `vscode-jsonrpc 9.0.3`, `proper-lockfile 4.1.2`; every resolved integrity is retained in `runtime/package-lock.json`.
- [C] Root non-peer declarations are `cross-spawn ^7.0.6`, `@ian-pascoe/pi-utils ^0.10.0`, `vscode-languageserver-protocol ^3.18.4`. Do not substitute semver ranges for the lock in a Nix build.

### Settings, PATH and opt-outs

- [H] Merge `recommended-settings.json`'s `lsp` object into the Nix-rendered **agent-directory** `settings.json`. It configures Go, TS/JS, nixd, Basedpyright and Ruff, uses separate language IDs for JSX/TSX, and sets `requireRootMarker: false` so standalone supported files are not silently omitted. Root markers still select project roots when found.
- [H] Supply PATH tools from nixpkgs: `gopls`, `go`, `typescript-language-server`, **`typescript_5`**, `nixd`, `basedpyright`, `ruff`, and `nodejs_24`. `nil` can replace `nixd`; `pyright` can replace Basedpyright with corresponding command/settings changes. Optional additions: `rust-analyzer` plus Rust toolchain, `bash-language-server` plus ShellCheck.
- [H] Generate the TypeScript initialization path from `${pkgs.typescript_5}/lib/node_modules/typescript/lib/tsserver.js`; the JSON artifact contains this lab's exact realized store path. This avoids a runtime package install and TypeScript 7 incompatibility.
- [C] `initializationOptions.disableAutomaticTypingAcquisition: true` disables TS's automatic @types acquisition. [H] Set `GOTELEMETRY=off`; for strictly offline Go analysis also set `GOPROXY=off`, `GOSUMDB=off`, `GOTOOLCHAIN=local`, understanding that missing module dependencies then produce incomplete analysis instead of being downloaded.
- [C] The recommended extension has **no plugin-level network/telemetry/installer path to opt out of** in the inspected source. Servers run the configured argv with inherited environment; their independent egress policy still matters.
- [H] Prefer absolute Nix executable paths in the generated production server definitions, or prefix a trusted Nix runtime PATH before repo-controlled bins. Do not expose provider credentials to server processes unnecessarily; the extension supports per-server environment null removal.
- [C] Global settings are always read, project settings only when `ctx.isProjectTrusted()` permits them. Global trusted server commands work even with `--no-approve`; the laboratory's successful recommended runs used that mode.

### Footer ownership

- [E] `ian-patched-status-bridge.ts` captures the public `lsp_status` ToolDefinition during upstream registration, reads its `structuredContent.servers` after lifecycle/tool events, and calls **`ctx.ui.setStatus("lsp", …)` only**. It never starts a server merely to ask status and never calls `setFooter`.
- [C] A replacement footer must render `footerData.getExtensionStatuses()` or it hides every extension status. The visuals evaluator confirmed its two proposed stacks expose `extension_statuses` / `footerSegments.extensionStatuses` respectively.
- [H] For final integration, prefer an upstream state-change/status callback over polling. The thin lab bridge refreshes on session/tool/agent events, so a process that crashes while Pi is idle can retain a stale badge until the next event. This limitation is UI-only; tool requests still surface client failure.

## Candidate-by-candidate audit

[C] Unless marked [E], entries below are source/doc observations, not live execution. All root package metadata is exact in `metadata.json`; native and bundled lifecycle details are exact in `native-inventory.json`. “No remote telemetry found” means no such path was found in inspected extension code, not a certificate for arbitrary configured servers or every transitive dependency.

### 1. pi-lens 4.4.4 — working, but not thin and not fully disable-able by the two installer switches

- [E] 24,932,447 bytes unpacked; MIT; its native `@ast-grep/napi` parser loaded and parsed JavaScript with lifecycle scripts skipped. Trusted real Go/TS edits returned diagnostics; both servers were discovered from the lab PATH after the TypeScript layout adapter.
- [C] Runtime dependencies include js-yaml, pidusage, minimatch, @ast-grep/cli, @ast-grep/napi, vscode-jsonrpc. Its prepare script builds, downloads grammars, installs Git hooks and warms loader caches; **never run it**. Bins: `pi-lens`, `pi-lens-mcp`, `pi-lens-analyze`. The tarball contains 13 WASM/native-suffix files, with native platform addons supplied by dependencies.
- [C] Configuration: explicit `PI_LENS_CONFIG_PATH`, normal user/project `.pi-lens.json` layers, `PI_LENS_HOME` for state. Installer switches: `PI_LENS_DISABLE_TOOL_INSTALL=1`, `PI_LENS_DISABLE_LSP_INSTALL=1`. Global format/autofix disables can be overridden by project configuration; CLI `--no-autoformat --no-autofix` are stronger.
- [C] Hooks modify tool results and also use turn/context/advisory injection; tools include `lens_diagnostics` and a dynamically activated `lsp_navigation` with definition, references, hover, symbols, rename and code actions. Persistent status is `setStatus("pi-lens-lsp", …)`; diagnostic widgets add editor-adjacent rows, not a replacement footer.
- [C] **Separate grammar-download path:** `dist/index.js:53807-53813` fetches a missing mapped grammar; `:56632-56643` gates it on trust/writeability, not either installer environment switch. There is no dedicated grammar-download disable setting in this release. An immutable Nix grammar directory blocks it before fetch, but that is a packaging boundary, not a config/env network kill switch.
- [E] Trusted smoke made no observed external network call. Guard denials were `npm config get prefix` discovery probes, **not npm installs**. Untrusted smoke intentionally refused LSP startup; its Go result's clean label was unsafe for this fixture.
- [H] Keep excluded for the requested thin stack: native/build/state footprint, ancillary scanner/context/read-guard behavior, missing independent grammar-download opt-out, and mutation policy are substantially broader than LSP.

### 2. @piex-dev/lsp 0.3.0 — closest small stock candidate; fails freshness

- [C] 73,609 bytes; MIT; no non-peer dependency, native module, bin or lifecycle hook. One ~1748-line TypeScript entry and a baked server catalog.
- [C] Config is baked defaults plus `PI_<SERVER>_LSP_COMMAND` argv strings; `PI_LSP_DIAGNOSTICS_ON_EDIT=0` disables its default-on hook. No general JSON server-config loader or trust check; project-local `.bin`/venv discovery precedes PATH unless overridden with absolute commands.
- [C] Successful edit/write `tool_result` mutation starts matching servers and appends errors only; it is silent on clean, failure and unconfirmed results. Unified `lsp` supports all requested navigation/refactor categories plus format/status/reload. No `setStatus` or `setFooter` call exists.
- [C] Spawns local stdio servers and writes only for explicit format/rename/action application, including resource edits. No installer/network/remote telemetry path found.
- [E] Fast real Go/TS diagnostics and navigation work normally; delayed real diagnostics produced both a cold miss and a stale error on a repaired file. Disqualified without a nontrivial freshness/error-handling patch.

### 3. @ian-pascoe/pi-lsp 0.15.1 — recommended with named narrow patch + status adapter

- [C] 563,930 bytes; MIT; non-native dependencies listed above; no bin or lifecycle installer script. No built-in server catalog/downloader: commands and languages are explicit global/trusted-project `settings.json` definitions.
- [C] Native `edit`/`write`, recognized apply_patch, and its own apply tool feed fresh outcomes into `tool_result.content`. It records pre-edit findings to avoid repeating old warnings and optionally checks affected dependent files. Separate custom entries render diagnostic UI but are model-invisible; model evidence is still in the tool result.
- [C] Direct model tools include `lsp_status`, `lsp_diagnostics`, `lsp_hover`, `lsp_goto_definition`, `lsp_find_references`, document/workspace symbols, `lsp_rename`, `lsp_code_actions`, `lsp_apply`; additional operations have codemode exposure. `/lsp` is a server-management picker. Upstream has no persistent status/footer contribution.
- [C] Spawns configured local commands with `shell:false`; writes private stderr/session spill files, explicit settings changes on scoped `/lsp` enablement, and validated workspace edits through `lsp_apply`. No installer/network/remote telemetry call found in inspected source. Workspace edit application is not a user confirmation gate and can target outside cwd when the configured server returns such edits.
- [E] Stock automatic diagnostics fail for the two requested push-only servers; patched automatic feedback, normal navigation and delayed freshness succeeded.

### 4. @narumitw/pi-lsp 0.49.10 — explicit diagnostics/fixes only

- [C] 266,690 bytes; MIT; no runtime dependency/native module/bin/install/postinstall/prepare hook. Trusted `.pi/pi-lsp.json`, then user `~/.pi/agent/pi-lsp.json`, then built-in catalog; custom map replaces catalog. Commands are argv arrays.
- [C] Registers only `lsp_diagnostics` and `lsp_fix`; starts/stops servers per call. No post-edit diagnostics hook, navigation, semantic rename or persistent server. `setStatus("lsp", "<server> <activity>")` is transient and cleared after calls, not a replacement footer.
- [C] No server downloads; spawns configured local commands, writes only explicit `lsp_fix(write:true)` output. No remote telemetry path found. Disqualified on missing requirements; no live run needed.

### 5. @signalridge/pi-lsp 1.2.7 — same functional exclusion

- [C] 110,149 bytes; MIT; dependency/native/bin/lifecycle-free. Canonical user/trusted-project `pi-lsp.json`, defaults, legacy `lsp.json` support; custom maps replace defaults; old PI_LSP_CONFIG/PI_*_LSP_COMMAND overrides were removed.
- [C] `lsp_diagnostics`/`lsp_fix`, spawn-per-call, no auto-edit feedback/navigation/semantic rename; transient `lsp` setStatus only. No downloads; explicit fix writes. No remote telemetry found. Disqualified before execution.

### 6. @wbline/pi-lsp 1.4.0 — auto-install-first, no navigation/write hook

- [C] 498,275 bytes; MIT; root runtime dependencies/native/bin/lifecycle-free. Registers `lsp_checks`, `lsp_diagnostics`, `lsp_fix`; built-in server/CLI catalogs, no normal global config format documented.
- [C] Defaults enable missing-tool installs; per-call `autoInstall:false` is the advertised opt-out, so the model can re-enable it. Installer paths spawn package managers/UV/bootstrap scripts; Windows jdtls downloads JDK/server archives via fetch. Managed paths include `~/.local/bin` and `~/.pi/agent/lsp`; startup also prunes jdtls state.
- [C] No automatic edit feedback or definition/references/rename tools. Status keys include `lsp`, `lsp:<server>`, `lsp-checks:<server>`, cleared after calls. Explicit fix writes plus installer/cache writes. Disqualified before execution.

### 7. pi-agent-ide 0.8.4 — a full IDE replacement, not a thin LSP plugin

- [C] 14,813,687 bytes for the root tarball; MIT; no root bin/lifecycle scripts. Large non-peer graph is fully retained in metadata: native node-pty, @ast-grep/napi, canvas, screenshot, formatter and tree-sitter dependencies; web/PDF/image/browser/SSH/editor packages. Native lifecycle handling would require a separate Nix packaging audit.
- [C] Config is global Pi `pi-agent-ide` settings plus project plugin/tool config; changes replace the tool/editor/resource surface. Its owned mutation pipeline schedules post-edit diagnostics, buffering findings by default for five seconds; noPostProcessing disables those diagnostics. This is not a small hook on stock tools.
- [C] Navigation and semantic rename are exposed through read/search/select/change abstractions, not the requested conventional six-tool interface. Inspected LSP sources have no server `setStatus` contribution; process widgets/status are separate (`agent-ide-processes`).
- [C] Local command execution, broad filesystem writes, opt-in doctor config writes, browser/web HTTP and SSH remote execution are present. Remote operations are explicit tool surfaces, not proof of background telemetry. Disqualified for scope; no runtime install or cloud endpoint used.

### 8. @mrclrchtr/supi-code-intelligence 11.0.1 — broad and explicit-health-oriented

- [C] 59,261,144 bytes; MIT; dependencies yaml, ignore, smol-toml and four Supi runtime packages; bundled WASM/TypeScript/runtime files; 18 native/WASM-suffix files found; no root lifecycle hook/bin.
- [C] Settings use a global/project `lsp.servers` namespace, with fileTypes without leading dots and explicit custom server commands. Tools: code_orientation, code_resolve, code_inspect, code_graph, code_find, code_health, code_refactor_plan, code_refactor_apply. An optional overview injects first-turn context by default.
- [C] Its post-edit `tool_result` recovery (`src/substrate/lsp/recovery.ts`) only notes workspace writes for later **explicit** health/semantic queries; it does not append automatic diagnostic evidence to every edit.
- [C] UI uses `setStatus("code-intelligence", …)` and widgets; `/supi-ci-status` temporarily owns `setFooter` and resets it with `setFooter(undefined)`, which conflicts with another footer owner's restoration expectations.
- [C] No server installer; configured stdio process execution, local diagnostic/debug/session-state writes, and explicit validated refactor writes. Debug “telemetry” refers to retained local events in inspected docs; no remote telemetry endpoint found. Disqualified on automatic-feedback requirement and footprint.

### 9. @spences10/pi-lsp 0.0.49 — good explicit diagnostics, not writethrough

- [C] 165,561 bytes; MIT; three runtime dependencies: pi-child-env 0.1.10, pi-tui-modal 0.0.24, pi-project-trust 0.0.19. No native/bin/install/postinstall/prepare root hook. Built-in PATH/project discovery; MY_PI_LSP_PYTHON_SERVER, MY_PI_LSP_PROJECT_BINARY, child-env allowlists and idle timeout are configured with environment variables.
- [C] Tools provide diagnostics, diagnostics_many, hover, definition, references, document/workspace symbols; no semantic rename/code-actions tool. `before_agent_start` adds a reminder to run checks; there is no automatic post-edit hook.
- [C] `/lsp status` is a command/modal; no `setStatus` or replacement footer in inspected runtime. Spawns local servers/version probes with restricted environment and project-binary trust prompts; no downloader/remote telemetry found. Disqualified before execution.

### 10. pi-lsp-extension 1.4.0 — earlier exclusion confirmed

- [C] 215,628 bytes; MIT; vscode-languageserver-protocol plus web-tree-sitter/tree-sitter-wasms; WASM/native dependencies, no root bin/install/postinstall/prepare hook. User runtime `/lsp-config` settings and per-project `.pi-lsp.json` support command/args/env/init/settings, autoStart and autoInjectDiagnostics.
- [C] Tool-result syncing on read/write/edit; diagnostic enrichment only when a matching client is already running, then a fixed 1500 ms cache wait. Tools cover every requested category, with rename preview only; additional completions/AST tools. Status is persistent `setStatus("lsp", …)`, no footer ownership.
- [C] Spawns local language servers and optional shared background daemons, writes socket/daemon/session/config state and explicit structural rewrite output. No runtime server installer/remote telemetry found.
- [E] Cold NEXT requests omit diagnostics. Eager-start `.pi-lsp.json` is honored with `ctx.isProjectTrusted() === false`: `extension-warm/events.jsonl` records false while `rpc.jsonl` records startup before any model tool. Thus untrusted-project startup remains a real gap.
- [E] Delayed real-gopls output caused stale errors after repair. This confirms the repo's cold/stale/untrusted-startup exclusion with both code and execution, rather than treating the old note as a conclusion.

### 11. pi-diet-lsp 0.1.9 — intentionally no automatic diagnostics

- [C] 38,553 bytes; MIT; zero dependencies/native/bin/lifecycle hooks. User `~/.pi/agent/pi-diet-lsp/config.json`, built-in PATH server candidates; config/commands toggle enabled/showStatus and language overrides.
- [C] Definition, references, symbols, hover, diagnostics only. Explicitly no edit pipeline/context injection/rename/code-actions. `setStatus("pi-diet-lsp", "LSP Active (N)"|"LSP Inactive")`; no footer owner.
- [C] Spawns local servers; preference toggles write a temporary JSON then rename it. No downloads/network/remote telemetry found. Disqualified on requirements.

### 12. @xynogen/pix-diagnostics 0.4.3 — good automatic evidence, missing actions/status inventory

- [C] 90,543 bytes; MIT; vscode-jsonrpc, pix-pretty, pix-runtime; no native/bin/root lifecycle hook. Project `.pi/lsp.json` explicitly configures servers; does not install/select them.
- [C] `tool_result` on successful write/edit performs checks and appends `LSP after <tool>` evidence including unavailable/unconfirmed states. Optional pix.json syntax guard can roll back a newly bad edit. No need to confuse that guard with the default diagnostics hook.
- [C] Tools are `lsp_diagnostics`, `lsp_navigation` (definition/type/implementation/references/hover/symbols/rename preview/call hierarchy), plus a diagnostic disposition tool. There is no code-action operation.
- [C] Uses diagnostic widgets under key `pi-lens-lsp`; `setStatus` calls in this package only clear that key at lifecycle boundaries, not a live server inventory. Local stdio clients, optional rollback writes, no installer/network/remote telemetry found. Disqualified on full action/status coverage.

### 13. pi-lspconfig 0.0.1 — on-demand navigation, dirty marking only

- [C] 302,794 bytes; MIT; jiti and vscode-jsonrpc; no native/bin/lifecycle hook. Executable TypeScript `pi-lspconfig.config.ts` user/project config deep-merges built-in specs; project code is trust-gated.
- [C] Unified `lsp` supports all requested semantic operations; `lsp_diagnostics` is separate. The edit/write `tool_result` hook only `markDirty()`s the file for its **next explicit** LSP query (`src/extension/lifecycle.ts:220-238`). No automatic diagnostics injection.
- [C] `setStatus("pi-lspconfig", "N servers")` reports configured count, not live states; no footer owner. Auto-install is off by default but per-server autoInstall can run an opted-in shell installCommand; stdio servers and explicit refactor writes otherwise. No remote telemetry found. Disqualified before execution.

### 14. @gitawego/pi-lsp 0.1.0 — progressive design, but broken config plumbing and wrong hook

- [C] 129,682 bytes; MIT; non-peer dependencies include typebox and full Pi AI/coding-agent packages rather than peers, risking a second runtime graph. No native/bin/root lifecycle hooks.
- [C] Docs describe user/project pi-lsp.json, per-server autoDownload, progressive.inject status/widget/conversation/none. Code entry calls `loadConfig({cwd,trusted})`; loader reads only optional userConfigPath/projectConfigPath, neither supplied by that entry, so ordinary configured files are not loaded (`extensions/pi-lsp.ts:59-60`, `src/config.ts:79-81,121-123`).
- [C] Intended progressive injection runs at `turn_end` using event.toolResults, not awaited per-write tool-result mutation; conversation mode uses `sendMessage`. Status uses key `lsp`. Query tools cover navigation and rename preview; fixes use source actions.
- [C] Auto-download implementations can invoke npm/go install, fetch GitHub releases, and write a managed cache. Code/docs disagree about defaults; no immutable runtime-download policy can safely depend on the documented override while config is not read. Disqualified without running installers.

### 15. @lukisxyz/pi-add-code-diagnostic 1.1.0 — command runner, not LSP

- [C] 21,611 bytes; MIT; Effect ^4.0.1; no native/bin/root lifecycle hooks. Per-repository config is under `~/.pi/repos/<root-sanitized>.json`, containing check/fileCheck/enabled.
- [C] Post-edit hook launches a background CLI file check; agent-settle runs the global CLI check and injects follow-up messages, potentially retriggering a turn. No definition/references/hover/rename/symbol/code-action tools, server lifecycle or LSP footer.
- [C] Config discovery is opt-in. Commands may be wrapped in bash for shell operators, config commands write/delete JSON, checker subprocesses run with 30/120-second limits. No package downloader/remote telemetry found in inspected code. Disqualified as the wrong capability.

## Prior-art recheck

- [C] Read-only prior implementation had `buildNpmPackage --ignore-scripts`, autoPatchelf for ast-grep, the TypeScript launcher layout adapter, installer opt-outs, scoped runtime directories, and a documented missing-grammar network exception. Sources: worktree `packages/pi-lens.nix`, `modules/home-manager/pi-codeintel.nix`, `tests/pi/codeintel.mjs`, `docs/pi.md:136-197`, plan Task 3.
- [E] The native ast-grep gate passes on this Linux host without lifecycle scripts. Trusted Lens discovers the tested Go/TS servers and returns real type errors. Therefore “Lens excluded” is **not** evidence that native addons or PATH discovery inherently fail.
- [C] The no-download policy still needs the separate grammar boundary; the two advertised installer variables are insufficient on their own. No kernel no-egress qualification was possible here.
- [E] The earlier pi-lsp-extension cold/stale/untrusted startup notes were independently reproduced as described above.

## Own thin implementation fallback

- [H] Prefer the small ian eligibility patch over writing another JSON-RPC client: its version handling, cancellation, UTF encodings, workspace-edit validation and diagnostics state already address the bugs observed in smaller clients.
- [H] If local upstream patches are unacceptable, a precise fallback is a ~800–1500-line TypeScript extension plus ~800–1500 lines of tests, reusing pinned `vscode-jsonrpc/node` and `vscode-languageserver-protocol`; a handwritten framing/parser implementation is not recommended. This is a size estimate, not measured implementation work.
- [H] Configuration: one Nix-generated global JSON server map with command/argv/languages/rootMarkers/initOptions/settings/env, no project executable config, no installer, network client, native grammar or package-manager lookup. Resolve allowed server executables from absolute Nix paths or trusted PATH; track one client per server/root/config identity.
- [H] Lifecycle: lazy initialize after `session_start` or first relevant tool, explicit starting/running/failed/stopped states, bounded initialize/request/shutdown deadlines, cancellation and process-exit rejection; shutdown every owned process. Handle workspace/configuration and capability registration; reject unsolicited workspace/applyEdit unless the extension deliberately implements that mutation contract.
- [H] Per-file sync: normalize URI; guard regular files; negotiate UTF encoding; increment versions on changed bytes; didOpen/didChange/didSave as supported. Cache diagnostics with server, URI, version and input generation. Never reuse an older version as current, and never turn silence/timeout into clean.
- [H] Writethrough: awaited `tool_result` for every successful edit/write, plus explicit recognized multi-file mutations; start the matching server even when cold. Prefer pull where advertised, otherwise require a fresh current-version push. Append bounded findings or explicit clean/unavailable/unconfirmed to the existing tool result. Preserve mutation success/failure, images and details. Optionally deliver a version-checked late result via an injected message when the bounded synchronous wait expires; never claim that late delivery was synchronous.
- [H] Tools: a single `lsp` tool with definition/references/hover/document+workspace symbols/rename/code_actions/status actions, 1-based public positions. Rename and actions should preview validated WorkspaceEdits, then an explicit apply path should validate versions/content, reject overlaps/path surprises and apply all text/resource edits safely. Command-only actions need an explicit allowed-command policy, not arbitrary execution.
- [H] UI: only `setStatus("lsp", …)` and state-change updates, no setFooter/setEditor. Footer owner consumes extension statuses. No syntax-highlighting, word completion, role routing or unrelated diagnostics framework in this extension.
- [H] Main risks are push-only servers that publish no clean notification, unversioned or out-of-order diagnostics, UTF conversion, multi-file atomicity, cancellation/process leaks, multiple complementary servers and untrusted server/project settings. A 100-line “thin LSP client” would omit the hard parts demonstrated by this lab.

## Unresolved integration checks / intentionally unclaimed behavior

- [H] Run the final Nix build with lifecycle scripts disabled and immutable source/dependencies, then the same real-Pi fixture against the produced derivation. No Nix repository changes or switch were made here.
- [H] Extend the acceptance fixture to nixd or nil, Basedpyright/Pyright plus Ruff, missing executables, clean push-only silence, unversioned diagnostics, server crashes, cancellation and concurrent edits. These were not exercised in this lab.
- [E] Semantic rename **preview** was exercised, not `lsp_apply`'s multi-file mutation or every code-action execution path. [C] Command-only refactor actions remain a documented gap relative to OMP's executeCommand support.
- [H] Own-tool mutations and read-only child sessions need the main integration's permission/role policy. Tool annotations are not an authorization boundary; the extension's apply tool can write, and custom server argv is executable configuration.
- [H] The recommended status bridge is event-refreshed, not continuous idle process monitoring. It proved footer coexistence through the setStatus contract and the default footer; the actual chosen custom footer's final combined rendering remains the coordinator's integration check.
- [C] No automatic format-on-write is enabled by this recommendation. That is deliberate scope separation, not a claim of OMP formatter parity.
