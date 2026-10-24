# Native OMP Work Trial Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Restore OpenCode and add configured native OMP without replacing Pi or changing Razer.
**Architecture:** Official source-built OMP, native Nix-generated profile, a supported provider/policy extension and shared owned Headroom lifecycle engine with OMP PID leases.
**Tech Stack:** Nix/Home Manager, OMP 18.12.6/Bun, TypeScript/JavaScript, Python.
**Spec:** docs/superpowers/specs/2026-10-22-omp-work-trial.md

## Global Constraints

- Framework-only; keep Pi/OC/OMP code, auth, settings and runtime ownership separate.
- Source pin 45c35e40; targeted omp lock addition only; no new cache trust.
- Runtime secrets/project identity never enter store; source files and templates only.
- Mandatory owned inference proxy, native MCP memory only; no direct fallback.
- User approved native title-off/Tuios limitations and activate-each-when-verified.

## Review Focus

1. Native provider auth/catalog/header semantics differ from modern Pi (Task 2).
2. Restart/fork and per-session shutdown must not lose process proxy ownership (Task 2).
3. Native task tool lists don't remove inherited MCP/extensions (Task 3).
4. Foreign config/profile/environment must not silently use Pi auth or another provider (Task 3).
5. Writable OMP main config must not conflict with immutable files or leak secrets (Task 3).

### Task 1: Restore OpenCode and pin/build OMP

**Files:** Framework user config, zsh alias, checks.nix, openspec-pi.nix, flake.nix/lock.
**Produces:** restored OC work settings/aliases and source-built OMP package.
- [x] Contract RED for restored OC, then enable work provider/routing/OpenSpec and restore oc alias.
- [x] Shared OpenSpec CLI duplication contract RED→GREEN; both skill sets retained.
- [x] Preserve existing live CLI preferences and backup regular file before declarative restoration.
- [x] OC/Headroom/config/OpenSpec/format/UI checks and activation build pass; activate with consent.
- [x] Targeted omp lock; preserve all existing locked sources; source build/install checks pass.

### Task 2: Native provider and owned process transport

**Files:** packages/headroom-pi.py, tests/headroom-omp.py, dotfiles/omp/provider-core.mjs, tests/omp/provider.mjs.
**Interfaces:** helper `--config FILE --acquire PID` → JSON `{stateDir,instance,proxyURL,project,memoryDB,leasePath}`; config `client="omp"` isolates registry. Core `createProviderService(options, deps)` supplies resolved bearer, current owned transport and authoritative native model rows; no bound ExtensionAPI shared.
- [x] Tests RED for OMP namespace/idempotent PID lease and proxy isolation; implement acquire API preserving existing Pi defaults/tests.
- [x] Core auth/catalog/metadata/route tests RED→GREEN using fake fetch/acquisition; bounded timeouts/attempts, explicit project validation and dual APIs. Metadata streaming/redirect hardening remains a recorded minor.
- [x] Native compiled CLI wire tests assert Chat/Responses and stopped-proxy refusal with no direct inference.

### Task 3: Native work profile, scoped policy and workflow parity

**Files:** modules/home-manager/omp.nix, dotfiles/omp/work.ts, tests/omp/*, checks/omp.nix, module imports and Framework enablement.
**Consumes:** Task 2 acquire JSON/core; native schema reports linked in spec.
**Produces:** programs.omp via upstream writable generator, managed work wrapper/profile/agents/MCP/skills/context, native UI untouched.
- [x] Config/schema/role/isolation/read-only direct+nested+xdev tests RED→GREEN; factory keeps gates even when provider initialization fails.
- [x] Package runtime SOPS wrappers and native MCP schemas; no store credential value or shared auth DB. Real MCP/SOPS connectivity remains user-trial evidence, not claimed by synthetic tests.
- [x] Generate native role/skill/command/context and Tuios integration; disable extra side-model work except explicitly accepted native Luna titles/skill summaries.
- [x] Native fake-service end-to-end model/lease/config loading, scout read/write-refusal, parallel async/follow-up tasks and stopped-proxy checks pass in Nix sandbox. Remote compaction is declaratively disabled; a real context-full compaction is not exercised.
- [x] Exact Framework/Razer evals, activation build and composed checks pass; activate per user consent. 29-output composed run passed; generation `sc5rf2zwd4qdxlhqjbw948ylmk3zqhdj` activated and `omp/18.12.6`, writable mode-600 config, managed companions and all three commands verified. No paid/live inference or Tuios restart.
- [x] Sonnet 5.5 xhigh whole-delta review, test-backed important fixes and complete report/dispositions (docs/reviews/2026-10-23-omp-work-*).
