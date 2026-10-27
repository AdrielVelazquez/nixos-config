---
title: Avoid rebuilding Python test harnesses when changing Headroom runtime dependencies
module: packages/headroom-path-python-dependencies.nix
date: 2026-10-27
problem_type: tooling_decision
component: tooling
severity: medium
applies_when:
  - "A narrow Python runtime override schedules unrelated native rebuilds"
  - "An exploratory scope appears cheap but the actual flake installable does not"
tags: [nix, python, headroom, scopes, dependencies, verification]
---

# Avoid rebuilding Python test harnesses when changing Headroom runtime dependencies

## Context

The Headroom upgrade needed newer Filelock and MCP without changing global
Nixpkgs. Its scoped Python dependency graph unexpectedly scheduled PyTorch,
ONNX Runtime and Mypy rebuilds, although the locked binaries were sufficient for
their intended roles. An early exploratory expression looked cheaper than the
actual Home Manager installable.

## Guidance

Capture the original Python package set at the caller and pass it into the scope
helper. During this investigation, `inherit (prev)` did **not** retain the original
harness graph: the actual target still scheduled PyTorch. The explicit capture
in `packages/headroom-ai.nix` is intentional:

```nix
basePythonPackages = python3Packages;
```

`packages/headroom-path-python-dependencies.nix` then selects known-compatible
objects from that original set, rather than trying to freeze them through `prev`:

```nix
inherit (basePythonPackages) mypy pytest-xdist torch;
inherit (basePythonPackages) onnxruntime;
```

The first group is build/test infrastructure, not Headroom's Python runtime.
ONNX Runtime is different: it is a runtime dependency. Reusing it was justified
separately by its satisfied version floor and a dependency graph containing none
of the overridden modules. Do not generalize this into freezing arbitrary runtime
libraries just because their binaries are cached.

Inspect the **actual installable** after every scope correction:

```bash
rtk proxy nix build --dry-run --no-link .#homeConfigurations.cachyos-framework13.config.local.headroom.package
rtk proxy nix path-info --recursive .#homeConfigurations.cachyos-framework13.config.local.headroom.package
```

Use derivation dependency inspection to identify why a test harness is scheduled,
then check the resulting runtime module set independently. A build-only dependency
edge is not evidence that a module belongs in the installed Python environment.
Here, explicit capture reduced 153 remaining builds to 17 without disabling tests
or weakening dependency bounds. The resulting module set had no duplicates,
contained the new Filelock/MCP, and excluded the test harnesses and old Filelock;
real compression, proxy, OpenCode and Pi checks then passed.

## Applicability

Use this approach only after establishing which dependencies are test-only or
independently compatible. Keep the scoped runtime overrides that enforce upstream
requirements. Retiring those pins is tracked in `TODO.md`; the reusable lesson is
to validate the real consumer and its runtime graph, not just a toy override or a
successful import.
