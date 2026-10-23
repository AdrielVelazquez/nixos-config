# Adversarial review: audited Pi capabilities (`feat/pi-audited-capabilities`)

Reviewer: `llmplatform/claude-sonnet-5-5` (variant requested by user: xhigh). Read-only review.
Worktree `/home/adriel/.local/share/opencode/worktree/7b0a5e/framework-pi`, base `e26f29a`.

## Scope actually reviewed

- `git diff e26f29a` = 28 files, +4120/-9. At review time `HEAD` is `9b792cc`
  (`test(pi): verify audited capabilities across the managed stack`) on top of `67e4eb0`.
  The Task 3 changes named in the brief as "staged/unstaged" are already committed, so
  `git diff e26f29a` equals `HEAD`. `git status` shows only untracked `.serena/`.
- Read in full: the spec, plan and ledger; `modules/home-manager/pi-capabilities.nix`, `pi-routing.nix`,
  `pi.nix`; `dotfiles/pi/extensions/{web-fetch,ast-readonly}.ts`; `packages/pi-*.nix` and
  `pi-web-fetch/package.json`; `checks/pi.nix`; all new or changed `tests/pi/*`; `docs/pi.md`;
  the `TODO.md` entry; and the diff of every other changed file.
- Read from the pinned upstream store paths (read-only):
  - `pi-web-access@0.44.0`: `index.ts` registration and lifecycle, `extract.ts`, `fetch-params.ts`,
    `web-tool-core.ts` `fetchContent`/`getSearchContent`, `storage.ts`, `ssrf-protection.ts`, `utils.ts`.
  - `pi-ast-grep@0.4.2`: `index.ts`, `cli.ts` and `tools.ts` for run, scan, rewrite, outline and debug.
  - `pi-zentui@0.32.0`: grep-level review only (writes, network, timers, commands, config).
- Did not read the other agent's `feat/pi-feature-gaps` branch or worktree. Did not touch real
  `~/.pi`, credentials, the live Tuios daemon or any live inference. Did not run `nix eval`,
  `nix build` or any check.

## Method and evidence labels

- **REPRODUCED** means I ran a disposable synthetic diagnostic, listed below.
  Scratch files were in `/tmp/opencode/sg-review`, which I deleted after the review.
  The diagnostics ran the pinned store ast-grep 0.51.0 binary and Node 24.15 with
  `--experimental-strip-types` against copies or imports of the pinned store sources.
  No repository, index or HEAD file was touched.
- **CODE-READ** means established by reading code or tests, not executed.
- **HYPOTHESIS** means plausible but not demonstrated.
- Some of my tool output was compressed by the harness. Where it mattered I re-ran with
  narrower output.

## Verdict

**READY WITH REQUIRED FIXES. No Critical findings.** The structure holds up. Three Important
items should be fixed or explicitly dispositioned before any activation request:

- **I-1:** the "fixed CLI / empty config" claim is false for `ast_grep_scan`'s `config` parameter. REPRODUCED.
- **I-2:** the new Pi wrapper unconditionally overrides a caller-supplied `PI_CODING_AGENT_DIR`. REPRODUCED semantics.
- **I-3:** `scout`'s local `read` plus arbitrary-public-URL `fetch_content` is an undocumented
  data-egress channel. A design/risk acceptance, not a code defect.

I did not infer the outcome of the rerunning 13-output suite. Nothing I found depends on it.

## Strengths

- **Registration whitelist is real.** The AST adapter registers exactly five tools by name and fails
  closed if one is missing (`ast-readonly.ts:14-23`). The web adapter throws on any unexpected tool,
  on any command registration, and on `registered.size !== 2` (`web-fetch.ts:19,23,53`).
  Stripped web surfaces (`web_search`, `source_check`, `web_enable`, commands, shortcuts) are asserted absent
  from the real registry (`capabilities.mjs:11-12`).
- **Execute-boundary argument checking is correct.**
  - Unknown keys are rejected via `Object.hasOwn` (`web-fetch.ts:37`).
  - Mode is allowlisted (`:39`).
  - URLs are parsed, protocol-checked and credential-checked (`:40-47`).
  - `redirects` is forced to `same-origin` (`:48`).
  - The checks run on every call, including `get_search_content`, because `checkPolicy()` is first (`:36`).
  - `proxy`, `auth`, `prompt`, `model`, `mode: answer`, `forceClone` and `frames` are all witnessed as refused
    through the real nested path with no request leaving (`capabilities.mjs:49-53`).
- **Upstream hidden routes checked and closed under this policy (CODE-READ).**
  - With `redirects` forced, `extract.ts:595-599` refuses GitHub and YouTube routes before any extractor.
  - `providerOrder` collapses to `["http"]` (`:830-834`).
  - `extractViaHttp` refuses PDF when `pdf.enabled` is false (`:1335`) and images via `imageGateError` (`:1367`).
  - Raw mode is text-only (`:1355-1364`).
  - Local-video and local-path routes need a leading `/`, `./`, `../` or `file://`, which `new URL().href`
    normalisation makes impossible (`video-extract.ts isVideoFile`).
  - `answer` mode needs a host `answerFromPage`, which does not exist.
  - Defuddle is called with `useAsync:false`.
  - `get_search_content` reads an in-memory map keyed by id, so there is no path traversal.
- **Policy handling fails closed.**
  - Policy is deep-equal checked, so extra or changed keys are refused.
  - `PI_ALLOW_BROWSER_COOKIES` and `FEYNMAN_ALLOW_BROWSER_COOKIES` are scrubbed.
  - `PI_CODING_AGENT_DIR` is required, matching upstream's config-dir resolution (`utils.ts:11-15`).
  - Upstream's `saveConfig` is reachable only from the commands that are never registered.
  - The test mutates the policy file after load (unlink, write `{}`, unlink) and sees refusal with zero requests
    (`capabilities.mjs:54-62`).
- **Zentui persistence stays inert.** Its writer follows the symlink to the store path and creates the temp
  file next to it, in the read-only store, so `/zentui` saves cannot replace the managed `zentui.json`
  (`config.ts` `readConfigFileState`/`writeConfigAtomically`). The Zentui GitHub, quota and tick-polling
  machinery is demand- or config-gated. `projectRefreshIntervalMs: 0` disables the interval
  (`project-refresh.ts`: `if (intervalMs <= 0) return () => {}`).
- **Test design is credible.**
  - Capability tests use the real Pi SDK loader, a real `codemode` and real `ctx.executeTool` nesting.
  - Hostile ambient `AST_GREP_BIN` and a hostile project `sgconfig.yml` are set (`capability-host.mjs:15,20`).
  - Production policy and a loopback-exemption policy are separate entries running the same adapter code.
  - The PTY test drives real Pi fullscreen with real paste, Unicode, SGR mouse, resize, questions,
    the real Tuios parser (`agent-hook pi --explain`), two reloads and managed-file byte equality.
  - The composed Headroom and child suites assert that AST and web tools appear on the real wire,
    that rewrite is absent, and that Headroom's stopped-proxy refusal is still asserted.
- **Packaging is clean.**
  - Integrity-pinned tarballs and an `importNpmLock` closure of 212 packages, all from `registry.npmjs.org`
    with integrity and `hasInstallScript` empty. Built with `--ignore-scripts` and `--legacy-peer-deps`.
  - SDK peers are symlinked, with no upstream patch and no runtime install.
  - Zentui and pi-ast-grep have no runtime dependencies.
  - `pkgs.ast-grep` ships only `bin/ast-grep`, so there is no `sg` shadowing of the system `sg`.
- **Razer is unchanged.** Only Framework sets `local.pi`; the new options default false; the contract test
  asserts `razerEnabled == [false,false,false]`.
- **TODO.md entry meets the repo exception protocol** (reason, upstream link, obsolescence check, target).

## Findings

### Critical

None found.

### Important

#### I-1. `ast_grep_scan`'s model-controlled `config` parameter overrides the pinned empty ast-grep config
REPRODUCED (CLI-level, pinned ast-grep 0.51.0), CODE-READ for the tool wiring.

- **Where.**
  - `dotfiles/pi/extensions/ast-readonly.ts:9-12` prepends `--config <empty>` to every argv.
  - Upstream `src/tools.ts:745-747` (kept unchanged, schema at `:146-150`) appends `--config <model path>`
    after the `scan` subcommand when `config` is given with no rule.
  - Claims affected: `docs/pi.md:58` ("pins both the executable and empty CLI config ... automatic project
    rule discovery ... ignored"), `TODO.md` ("pin the executable/empty CLI config"), and spec
    "fixed CLI/empty config".
- **Evidence.**
  - `ast-grep --config pinned.yml scan --json=compact a.ts` returned `[]`.
  - `ast-grep --config pinned.yml scan --config <proj>/sgconfig.yml --json=compact a.ts`, which is the exact argv
    the adapter and upstream produce, returned the `no-console` match from the project's `ruleDirs`.
    clap rejects two top-level `--config` flags but silently accepts a subcommand-level one, so the later value wins.
- **Actual effect.**
  - Any role with `ast_grep_scan` (scout, explore, build, plan, and the primary session) can load any
    `sgconfig.yml` (ruleDirs, utilDirs, languageGlobs, customLanguages), including one from a hostile repo.
  - Pure rule loading is read-only.
  - Native custom-language libraries are currently not loaded, only because ast-grep 0.51.0 defaults to
    "ignore" (I confirmed: it printed "custom languages are ignored" and continued).
    That safety rests on an upstream default plus the user's ast-grep trust store, not on the pin.
    ast-grep also has `--custom-languages trust`, which persists per-project trust.
    Whether such state exists on the real home was not checked, because I did not read it (HYPOTHESIS).
  - The tool schema and its `promptGuidelines` also tell the model that "the project's sgconfig.yml rules
    are discovered automatically" (`tools.ts:724`), which is false under the pin.
- **Why tests did not catch it.** `capability-host.mjs:20` only plants a hostile `sgconfig.yml` in `cwd` for
  automatic discovery. No test passes `config`.
- **Suggestion.**
  - In `installReadOnlyAst`, wrap `ast_grep_scan` to delete `config` from `parameters.properties` and
    from `required`, and reject it in `execute`. Alternatively pass `--custom-languages ignore` in the
    runner prefix as a second layer. I checked that the flag is accepted as a global option.
  - Fix the model-visible description and guideline text for `ast_grep_scan`.
  - Add a regression: a project `sgconfig.yml` with a `ruleDirs` rule plus
    `ast_grep_scan {config, path}` must be rejected or return no rule matches.
  - Also reject or neutralise `outline_rules` and `rule_file` only if the policy is meant to forbid
    reading arbitrary YAML. Both are read-only, so this is optional.

#### I-2. The Pi wrapper unconditionally overrides a caller-provided `PI_CODING_AGENT_DIR`
REPRODUCED semantics (synthetic wrapper replica plus the real built wrapper text); CODE-READ.

- **Where.**
  - `modules/home-manager/pi.nix:19` adds `export PI_CODING_AGENT_DIR=<cfg.agentDir>` before the launcher exec.
  - The built wrapper `/nix/store/7lv1akcp0q98p9yjbk9268k3qfkcw462-pi/bin/pi` begins with
    `export PI_CODING_AGENT_DIR=/home/adriel/.pi/agent`.
- **Evidence.** A replica script with the same first line, run as `PI_CODING_AGENT_DIR=/tmp/throwaway ./wrapper`,
  executed the inner command with `agentdir=/home/adriel/.pi/agent`.
- **Actual effect.** Any invocation like `PI_CODING_AGENT_DIR=/tmp/x pi ...` now silently runs against the real
  agent directory.
  - That is the usual way to give Pi a throwaway or test config.
  - It is the practice this repo's own `AGENTS.md` endorses ("throwaway test configs under /tmp are fine; never
    write to the user's real config").
  - An agent or script following that guidance would now touch the real `settings.json`, `auth.json`, sessions
    and, via the new web cache, `web-search-cache/`. This is a safety regression introduced by this change.
- **Why it exists.** `web-fetch.ts:7` requires the variable, and upstream resolves its config dir from it.
- **Suggestion.**
  - Use `export PI_CODING_AGENT_DIR="${PI_CODING_AGENT_DIR:-<cfg.agentDir>}"`.
    A caller-provided directory without the managed `web-search.json` then fails closed in `web-fetch.ts:12-14`,
    which is the intended behaviour.
  - Add a test that runs the built wrapper with a stub inner command and asserts both the default and the
    override cases.

#### I-3. `scout` (and `build`/`plan`) combine local `read` with `fetch_content` to arbitrary public URLs, an undocumented egress channel
CODE-READ; design and documentation. Calibrated as a risk acceptance, not an adapter defect.

- **Where.**
  - `pi-routing.nix:36-53` grants `fetch_content`/`get_search_content` to scout, build and plan.
  - Scout keeps `read`, `grep`, `find`, `ls` over any path, plus `codemode`.
  - Docs: `docs/pi.md:35,63,70,75`.
- **Actual effect.**
  - The `fetch_content` description tells the model that retrieved content is untrusted (`web-fetch.ts:32`).
    A hostile page returned to scout can instruct it to read local secrets (read has no path restriction) and
    leak them by fetching `https://attacker.example/?d=...`. The same applies to path segments.
  - Same-origin redirects, the SSRF guard, no cookies and no proxy do not limit outbound data in a URL.
  - The docs describe scout as "read-only" and mention only SSRF/egress isolation caveats, never this channel.
    "Read-only role" language implies no exfiltration.
  - A previously audited decision, "scout may fetch", is not wrong. Its consequence should be acknowledged
    by the user.
- **Suggestion.**
  - State the channel in `docs/pi.md` and `TODO.md`.
  - Optionally reduce it in the adapter:
    - cap URL length, for example 512 characters, instead of the current 8192, which is plenty for exfiltration;
    - refuse `?`/`#` content for roles that do not need it, if feasible;
    - or require UI confirmation per host.
  - The user must accept the residual risk or choose to drop fetch from scout.

### Minor

#### M-1. Outline spill directories leak: only the first of two `ast_grep_outline` runs is tracked
REPRODUCED.

- **Where.** `ast-readonly.ts:17-22` tracks only `result.details.fullOutputPath`.
- **Evidence.** Upstream `tools.ts` runs `buildOutlineArgs("expanded")` a second time and does not report its
  spill. I ran the upstream outline tool through a synthetic runner (`TMPDIR=/tmp/opencode/sg-review/tmp`) on a
  directory of 120 TypeScript files. It created **two** `pi-ast-grep-*` temp directories but reported one
  `details.fullOutputPath`.
- **Effect.** A leaked temp directory of code outline per truncated outline call, never removed by
  `session_shutdown`. The docs promise cleanup of "only its own tracked full-output spills".
  Spills also leak when a tool throws after the spill is written.
- **Suggestion.** Import `cleanupSpillDirs` from the pinned `src/cli.ts` and call it on `session_shutdown`
  in addition to the tracked set. It already clears every spill created by this process's module instance.

#### M-2. Negative "rewrite is unavailable" witnesses are non-discriminating
REPRODUCED for the underlying behaviour; CODE-READ for the tests.

- **Where.** `capabilities.mjs:17-20`, `routing.mjs:37,176-177`.
- **Evidence.** I called the upstream `ast_grep_rewrite` tool directly with `apply:true`, no preview, `hasUI:false`.
  It refused with the preview-first policy and left the canary unchanged. A headless or UI-gated session also
  blocks the apply.
- **Effect.**
  - The nested `denied === true`, the `canary unchanged` assertions, and the child
    `STRUCTURAL_WRITE_WITNESS` (which asserts only `status === 'completed'` and the file) would all pass even
    if the rewrite tool were registered.
  - The regex at `capabilities.mjs:19` (`/not|unknown|undefined|available|found/i`) also matches almost any
    message.
  - The discriminating assertions are the registry check (`:12`) and the wire-tools check
    (`routing.mjs:171-172`, `headroom.mjs` composed tools). They are currently sufficient, but the Code Mode and
    nested witnesses certify less than their names suggest.
- **Suggestion.**
  - Assert the actual error text, as `CODEMODE_PROBE` already does for `probe_mutate`:
    `/ast_grep_rewrite.*does not exist|not available/`.
  - In the SDK test, do a preview call, then an apply call, so only absence can explain a refusal.

#### M-3. `required-integrations.mjs` does not assert that the generated production declaration contains the new ids
CODE-READ.

- **Where.** `tests/pi/required-integrations.mjs:16-19` asserts only `length >= 1` and `snapshot[0].id === 'managed-policy'`.
- **Effect.** `routing.mjs` and `routing-host.ts` take `required` from the fixture JSON, not from the generated
  `pi-required-integrations.ts`. The Nix-option-to-generated-file step is covered only by the config-level
  contract test, not by the real loader. This is the "missing child mandatory declarations" focus.
- **Suggestion.** Assert `snapshot.some(e => e.id === 'readonly-ast')` and `'fetch-only'`.

#### M-4. No direct witness that `explore` cannot reach web through Code Mode, and `get_search_content` is not asserted absent from `explore`
CODE-READ. By analogy to the `probe_mutate` canary this is likely fine (HYPOTHESIS), but not demonstrated.

- **Where.**
  - `roles.mjs:21` and `capabilities-contract.mjs:43` check only `fetch_content`.
  - `routing.mjs` probes only the `scout` role for Code Mode and nested misuse.
  - The explore child does load `fetch-only`, a required extension, so web tools are registered but not
    allow-listed.
- **Suggestion.**
  - Assert the same for `get_search_content`.
  - Add `/spike foreground explore` probes: a `codemode` call to `tools.fetch_content` must say the tool does
    not exist, and a direct `fetch_content` must be refused.

#### M-5. Upstream SSRF guard accepts several IPv6 forms that embed or route to private space; docs say "private-range access is denied"
REPRODUCED at validator level only (`validateRemoteUrl` on IP-literal URLs, no connections).

- **Where.** Pinned `ssrf-protection.ts`, `isBlockedIPv6`. Docs: `docs/pi.md:68,72`.
- **Evidence.** Under the production-equivalent options (`allowRanges: []`, `trustEnvProxy: false`):
  - blocked: IPv4 loopback and private forms, `::1`, `::ffff:x`, link-local, `::`, decimal/hex/short IPv4.
  - ALLOWED: `[64:ff9b::7f00:1]`, `[64:ff9b::a00:1]`, `[64:ff9b::a9fe:a9fe]` (NAT64), `[2002:a00:1::]`,
    `[2002:7f00:1::]` (6to4), `[64:ff9b:1::...]`, a Teredo address, `[fec0::1]` (site-local),
    `[::127.0.0.1]`, `[::ffff:0:7f00:1]`, and `[ff02::1]`.
- **Effect.**
  - Exploitability depends on the host network, for example a NAT64 gateway reaching RFC1918/metadata
    space, and is unlikely on a typical dual-stack laptop (HYPOTHESIS).
  - Production tests only cover IPv4 loopback.
  - The docs' "private-range access is denied" is stronger than what upstream provides.
- **Suggestion.**
  - Add the forms above to the production negative test as expectations.
  - Soften the docs.
  - Record an upstream follow-up in `TODO.md`. Do not patch upstream, per the spec.

#### M-6. Model-visible text drifts from the actual capabilities
CODE-READ.

- **Where.**
  - `pi-routing.nix:73,95` still describe scout as MCP-only ("through approved MCP operations", "using available
    approved read-only MCP tools").
  - Upstream `ast_grep_languages` and `ast_grep_scan` descriptions mention `rewrite` and automatic
    project `sgconfig.yml` discovery.
- **Effect.** The model may avoid `fetch_content` as out of scope, or attempt non-existent `ast_grep_rewrite`
  and `rule_file` discovery. This costs a turn, not safety.
- **Suggestion.** Update the scout role text, and override the AST descriptions in the adapter (see I-1).

#### M-7. Adapter mutates global process state
CODE-READ.

- **Where.** `web-fetch.ts:9-10` deletes `PI_ALLOW_BROWSER_COOKIES` and `FEYNMAN_ALLOW_BROWSER_COOKIES`
  from `process.env` on factory install and on every call.
- **Effect.** Defence in depth, but this alters the environment of the whole Pi process and its subprocesses.
  Harmless today because no other consumer exists.
- **Suggestion.** Keep it and add a comment, or scope the check to the upstream call.

#### M-8. No test for the "missing pinned binary never falls back" acceptance
CODE-READ.

- **Where.** Spec acceptance "missing binaries never install replacements". `capabilities.mjs` pins and ignores
  an ambient `AST_GREP_BIN`, but never points the adapter at a missing store path and checks for failure with no
  `PATH` fallback.
- **Effect.** True by construction, since `pi.exec` is called with the absolute store path, but unwitnessed.
- **Suggestion.** Add a unit test passing a nonexistent binary to `installReadOnlyAst` and asserting error text
  and no fallback.

#### M-9. Activation pre-flight: Home Manager clobber risk on new managed files (HYPOTHESIS)

- **Where.** `pi-capabilities.nix:106,149` adds `zentui.json` and `web-search.json` without `force`.
- **Effect.** Standalone Home Manager refuses to overwrite an existing regular file at
  `~/.pi/agent/zentui.json` or `web-search.json` (for example from an earlier manual `pi-web-access` or
  `/zentui` save). I did not inspect the real home. It would fail activation, not corrupt data.
  `~/.pi/agent/web-search-cache/` becomes a new 0700, 128 MiB, 1 h TTL on-disk content cache.
- **Suggestion.**
  - State the pre-flight in the handoff: check those two paths, or use `-b` for the first switch.
  - Correct `docs/pi.md:70` ("package/session runtime state") to say the content is persisted on disk under the
    agent dir, with TTL and limits.

#### M-10. PTY and composed-test coverage gaps (limitations, not defects)
CODE-READ.

- **Where.** `capability-ui.py`, `capability-ui-fixture.ts`.
- **Gaps.**
  - No agent turn is rendered through the Zentui editor. The provider is `127.0.0.1:1`. Only extension
    commands and dialogs are exercised, so streaming, tool rendering and Tuios `agent_start`/`agent_end` with
    Zentui active are unwitnessed.
  - The repo's own `question.ts` is not driven. The fixture uses `ctx.ui.select`, and `ctx.ui.input`
    (free-form answer) is not covered.
  - The ast-grep status (`ast-readonly.ts:27`) is not asserted visible.
  - `/zentui` is still registered. Saves fail safely, but the menu is live.
  - The 75 s overall `timeout` with several 15 s waits could cause a loaded-machine false failure, never a
    false pass.
- **Suggestion.** Add one scripted-model turn through the PTY if the fixture server can be made local.
  Consider hiding or no-oping `/zentui` in a registration proxy.

#### M-11. Adapter code is untyped and unchecked

- **Where.** `ast-readonly.ts` and `web-fetch.ts` use implicit-any parameters (`createTools`, `installUpstream`,
  `tool`) and have no `tsc` or lint step.
- **Effect.** Upstream shape changes surface only when the real-runtime tests fail, which is acceptable given
  the exact version pins.
- **Suggestion.** Optional: add `// @ts-check` plus minimal interfaces for the two adapter files.

#### M-12. Hygiene

- **Where.** Untracked `.serena/` in the worktree.
- **Effect.** Not part of the diff. Do not stage it.
- **Where.** `home.packages = [ pkgs.ast-grep ]` (`pi-capabilities.nix:140`).
- **Effect.** Puts ast-grep on the interactive `PATH`. Harmless, since the adapter uses the absolute path. It
  also lets users run `ast-grep -U` themselves, as they always could.

## Review-focus audit

1. **Nested/Code Mode reach to AST rewrite or stripped web params.**
   - Rewrite is never registered. Registry and wire assertions are strong (see M-2 for weak execution witnesses).
   - Stripped web args are refused at execute through the real nested path.
   - Gap: `ast_grep_scan.config` (I-1) is an unstripped model-controlled knob.
2. **Read-only child roles.**
   - Role text is correct (explore AST only; scout adds fetch/retrieval; no bash/write/edit/subagent).
   - Child wire list for scout is verified.
   - Gaps: no direct explore web witness (M-4); the egress consequence for scout (I-3).
3. **Missing/replaced web policy.**
   - Refuses at install and on every call, with a full deep-equal check; behaviour witnessed.
   - No broadening path found. The deletion of cookie env vars is a harmless extra (M-7).
4. **UI reload / immutable settings / Tuios lifecycle.**
   - Verified by a real PTY, including two reloads and managed-file preservation.
   - Zentui cannot replace store-linked files.
   - Gaps: no agent turn (M-10); the wrapper env regression (I-2) sits outside this check.
5. **Headroom fail-closed with added packages.** The stopped-proxy refusal assertions remain and the composed
   run includes the capability entries and the production web policy file. No bypass found; `fetch_content`
   goes direct HTTP and is orthogonal to the inference-only proxy.
6. **Hidden routes, parameter gaps, global state, child declarations, fixture-certifying tests.**
   - Hidden routes in `fetch_content` are closed; for AST, the `config`, `outline_rules` and `rule_file`
     parameters remain (I-1).
   - Argument-injection into ast-grep argv is not possible, because the tool uses an argv array with no shell,
     and `--lang`-style flags reject values starting with `-`.
   - Global state: `widgetVisible`, `storedResults` and the activity monitor are module-level upstream, but
     each load is a separate module instance, and the shortcuts and commands that drive them are removed.
     The spill leak is M-1.
   - Child declarations: M-3.
   - Fixture-certifying tests: M-2, plus the production loopback test covering only IPv4 (M-5).

## Assumptions and limitations

- I assumed the test results stated in the brief are accurate. I did not run any Nix check, eval or build.
  The brief's "do not infer the full-suite outcome" is respected.
- The I-1 reproduction used the CLI directly with the argv the adapter plus upstream produce. It was not run
  inside a Pi session. The argv composition is deterministic from the two code paths cited.
- I-2 used a replica of the wrapper's first line and the real built wrapper's text. I did not execute the real
  wrapper, to avoid any chance of touching the real agent directory.
- M-5 exercised only the validator on IP literals (no network I/O). Hostname paths and DNS rebinding use the
  same `assertPublicAddress`, so they inherit the same gaps (CODE-READ).
- The Zentui review was grep-level over about 37k lines. I did not audit its renderer or patch registry
  behaviour beyond persistence, network, timers and commands.
- I did not inspect the real home, ast-grep trust state or existing managed files.

## Declined to judge

- Live provider, Headroom and Tuios behaviour with real credentials, network egress and the daemon.
- Outcome of the rerunning 13-output suite, `nix eval` results for Framework and Razer, and the activation build.
- Zentui visual quality and non-editor rendering (disabled components).
- Trust-state of the user's real ast-grep installation, pre-existing real-home files that may conflict at
  activation (M-9), and whether the real Framework network exposes NAT64, 6to4 or site-local routes (M-5).
- The other agent's `feat/pi-feature-gaps` branch (not read, by instruction) and the rejected permission,
  LSP and Lens packages (not implemented, by design).
- Whether `scout` should have web at all (I-3). That is a product decision, not a code review.

## Suggested disposition order

1. I-1: strip `config`, add `--custom-languages ignore`, fix text, add the regression.
2. I-2: honour a caller-set `PI_CODING_AGENT_DIR`, add a wrapper test.
3. I-3: document the egress channel, or choose to mitigate; record in `TODO.md`.
4. M-2, M-3, M-4: strengthen negative witnesses and the child-declaration test.
5. M-1, M-5, M-6, M-9: spill cleanup, SSRF-form expectations and docs, role text, activation pre-flight note.
6. The rest as time permits.
