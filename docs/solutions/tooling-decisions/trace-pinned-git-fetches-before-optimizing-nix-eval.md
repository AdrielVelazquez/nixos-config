---
title: Trace pinned Git fetches before optimizing Nix module evaluation
date: 2026-10-29
category: tooling-decisions
module: flake.nix
problem_type: workflow_issue
component: tooling
severity: medium
applies_when:
  - "An unchanged host evaluation takes much longer than its CPU time"
  - "Cached exact-revision Git dependencies still cause SSH traffic during evaluation"
tags: [nix, git, evaluation, performance, benchmarking, flakes]
---

# Trace pinned Git fetches before optimizing Nix module evaluation

## Context

Framework Home Manager evaluation took 42–45 seconds but only about 10 seconds of CPU. Repeating the eval and adding `--offline` did not remove the delay. This initially looked like growing module/test overhead; process inspection instead caught evaluation-time `git ls-remote --symref` calls.

The installed Nix client rediscovered default branches for cached, exact-revision fetches in the Reddit package input. This was an evaluator issue, not a Nixpkgs package-set defect. A scratch explicit-ref workaround proved the mechanism, but changing dozens of package recipes was unnecessary once the upstream evaluator fix was identified.

## Guidance

Record wall time, child CPU time, current machine load, and Git commands separately. Set `GIT_TRACE2_EVENT` to a private scratch file for the evaluator process; count `cmd_name` events and inspect `start` arguments to distinguish local cache queries from remote queries. Never commit raw traces, which may contain private repository URLs or credential-bearing command arguments.

Compare the installed client with a candidate by absolute executable path against the same unchanged checkout. Freeze tracked edits during the comparison: unrelated tracked-file edits can change this flake's source store path and therefore the returned derivation.

Consume the fix directly from upstream Nix when available. [Nix PR #16494](https://github.com/NixOS/nix/pull/16494) skips default-branch discovery for exact revisions without an explicit ref, except when `allRefs` requires discovery. `flake.nix` exposes a locked upstream package as `packages.x86_64-linux.nix-upstream` and selects it as Framework system-manager's `nix.package`. Benchmark the candidate directly before activation; the separate daemon does not need replacement for this evaluator fix. The package has multiple outputs, so do not assume the first path printed by `nix build --print-out-paths` contains `bin/nix`: inspect the `out` output or verify the executable explicitly.

Test cold and warm remote-style Git fetches in an isolated local fixture as well as the real host eval. Require identical pinned contents and source hashes, no unnecessary cold discovery, and no warm refetch. A warm source-store hit alone is insufficient evidence.

## Why This Matters

The direct upstream executable evaluated the same Framework activation derivation in 10.154 and 7.886 seconds versus 44.843 and 42.188 seconds with the installed client. All four returned the identical derivation. Git discovery calls fell from 110 to 2 per eval; the remaining local/remote pair was for Smithay. Nixpkgs' Rust lock importer uses `allRefs = true`, a case the upstream fix intentionally preserves. Therefore asserting zero Git commands globally is the wrong regression test; require that the unnecessary pinned-fetch discovery disappears.

The candidate also emitted warnings about existing SCP-style Git URLs. Successful evaluation and matching derivations do not mean an upgrade is warning-free or fully validated for installation. Neither the running client nor daemon was replaced during the benchmark; the user subsequently activated Framework's managed CLI, and its version matched the locked upstream commit while the daemon configuration remained unchanged.

## When to Apply

Use this investigation before blaming module count, changing global caches, moving private source fetches into a build sandbox, or maintaining recipe-level workarounds. Keep authentication in the existing runtime SSH environment; never embed credentials in a flake URL, derivation, or trace committed to Git.

## Related

- [Source-path churn during flake refactors](nix-flake-drvpath-is-not-a-refactor-proof.md)
- [Benchmark CPU time under concurrent load](benchmark-pi-with-the-package-binary-and-cpu-time.md)
- [Upstream exact-revision discovery fix](https://github.com/NixOS/nix/pull/16494)
