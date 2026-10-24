# Audited Pi Capabilities Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Install the audited editor/read-only-AST/fetch-only profiles declaratively on Framework without changing Razer or existing authority/inference routing.

**Architecture:** A reusable opt-in Home Manager module packages three exact upstream artifacts. Small registration adapters constrain upstream AST/web surfaces; native child role allowlists remain authoritative. No upstream source patch or runtime installer.

**Tech Stack:** Nix/Home Manager, upstream Pi 1.3.0, TypeScript, Node 24, Python PTY fixtures.

**Spec:** `docs/superpowers/specs/2026-10-22-pi-audited-capabilities.md`

## Global Constraints

- Framework-only enablement; Razer unchanged; current provider/Headroom/subagents retained.
- Zentui 0.32.0 editor-only, pi-ast-grep 0.4.2 read-only, pi-web-access 0.44.0 fetch-only.
- No secrets, runtime installs, global yolo, new LSP, compaction-model routing, or live activation.
- Work independently of the other agent's branch; user requested immediate inline implementation.
- All new flake imports staged by exact path before eval. Every Nix change gets exact target eval.

## Review Focus

1. Nested/Code Mode access cannot reach AST rewrite or stripped web parameters (Task 2).
2. Read-only child role changes cannot grant web to local explore or writer/shell access (Tasks 1/3).
3. Missing/replaced policy must refuse web instead of silently broadening defaults (Task 2).
4. UI reload/immutable settings/native Tuios lifecycle stays intact (Task 3).
5. Headroom failure remains fail-closed with the added package composition (Task 3).

### Task 1: Pinned packages and declarative profile

**Files:** create `packages/pi-zentui.nix`, `packages/pi-ast-grep.nix`, `packages/pi-web-fetch.nix`, `packages/pi-web-fetch/{package.json,package-lock.json}`, `modules/home-manager/pi-capabilities.nix`, `tests/pi/capabilities-contract.mjs`; modify module imports, Framework user config, `checks/pi.nix`.

**Interfaces:** consumes audited npm identities/integrities; produces `local.pi.capabilities.{editor,ast,web}.enable` (default false), immutable adapter paths/sidecars and `pi-capabilities-contract`.

- [ ] Write contract asserting Framework flag/tool/config/role invariants and disabled Razer profile.
- [ ] Run `rtk nix build --no-link .#checks.x86_64-linux.pi-capabilities-contract`; expect missing capability failure against current configuration.
- [ ] Package exact sources/dependencies, define module, immutable sidecars and explicit Framework enablement; no other-agent code reused.
- [ ] Stage exact new files, run exact Framework/Razer evals and contract; expect PASS.
- [ ] Commit `feat(pi): declare audited capability profiles` after the task passes.

### Task 2: Narrow adapters and actual runtime tests

**Files:** create `dotfiles/pi/extensions/ast-readonly.ts`, `dotfiles/pi/extensions/web-fetch.ts`, `tests/pi/capabilities.mjs`, `tests/pi/capability-host.mjs`; extend check fixtures.

**Interfaces:** `installReadOnlyAst(pi, createTools, binary)` registers exactly five read tools; `installFetchOnly(pi, installUpstream, expectedPolicy)` registers exactly fetch/retrieval with restricted schema and execution validation.

- [ ] Write actual SDK tests for AST results, nested/Code Mode rewrite unavailability, explicit binary pin, fetch-only schema/redirects/private ranges, forbidden options and policy tampering.
- [ ] Run `rtk nix build --no-link .#checks.x86_64-linux.pi-capabilities`; expect absent-adapter/behavior failures before implementation.
- [ ] Implement minimal supported-factory adapters; no private APIs or upstream patches.
- [ ] Run runtime tests and contract plus exact target eval; expect PASS and no extra model calls/config writes.
- [ ] Commit `feat(pi): constrain structural search and web fetching`.

### Task 3: Composition, UI, documentation and final review

**Files:** add retained PTY fixtures/check; modify `tests/pi/headroom.mjs`, `tests/pi/routing.mjs`, `tests/pi/roles.mjs`, `docs/pi.md`, `TODO.md`.

**Interfaces:** consumes actual managed adapter paths/config, existing real provider/Headroom/child fixtures and Tuios hook.

- [ ] Add tests pinning visible editor, questions/Tuios, reload/status, mandatory child capabilities and unchanged role ceilings.
- [ ] Run targeted composition checks against the unmodified fixture composition; witness failing assertions before wiring adapters into fixtures.
- [ ] Wire managed capability fixtures into Headroom/provider/child tests; document exact versions, use, limits and removal gates.
- [ ] Run all Pi checks, configuration contract, formatting, exact Framework/Razer evals and full Framework activation-package build.
- [ ] Commit `test(pi): verify audited capabilities in the managed stack`.
- [ ] Dispatch user-required Sonnet 5.5 xhigh adversarial review, retain complete report, address important findings RED→GREEN and rerun relevant suite.
- [ ] Deliver review dispositions and activation handoff; do not merge/push/activate without required consent.

### Task 4: User-requested full visual mockup and review fixes

The user explicitly expanded the visual scope after the initial editor-only
activation. Keep the same branch and existing capability behavior; activation
of the expanded profile still needs consent.

- [x] Preserve complete original Sonnet report in `docs/reviews`.
- [x] I-1 and I-2 regressions RED, then strip scan config/native languages and honor explicit agent-dir overrides GREEN.
- [x] Document I-3 URL-based data-egress channel and upstream IPv6/cache caveats; user explicitly chose activation with fetch retained after disclosure.
- [x] Contract/PTY RED for missing complete visuals, then implement theme, public header/footer, framed user messages and builtin tool panels.
- [x] Actual scripted PTY turn through read/edit panels, native question tool/free-form input, Tuios, reload and managed-file preservation.
- [ ] Capture actual rendered screenshots; rerun full suite/build/evals with the expanded profile.
- [ ] Review the newly requested visual delta with Sonnet 5.5 xhigh (not a duplicate review of unchanged code).
- [ ] Publish complete findings/dispositions and request next activation consent; no merge/push.
