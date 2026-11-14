---
title: Keyless environments cannot evaluate framework13-derived checks - verify through narrower evals and CI
date: 2026-11-13
category: tooling-decisions
module: checks.nix
problem_type: workflow_issue
component: tooling
severity: low
applies_when:
  - "A check or eval that derives from homeConfigurations.cachyos-framework13 fails with an SSH fetch error instead of a code error"
  - "Verification must proceed on a machine where the private reddit-nix flake input is unreachable"
retire_when: "checks.nix stops deriving checks from homeConfigurations.cachyos-framework13 (grep for frameworkHome and legacyWorkHome) or the reddit-nix input becomes fetchable without a loaded SSH key"
tags: [nix, checks, evaluation, ssh, reddit-nix, verification, flakes]
---

# Keyless environments cannot evaluate framework13-derived checks - verify through narrower evals and CI

## Context

While validating the OpenCode Headroom port move (commit `1f6622b`, "fix(headroom): move OpenCode proxy off Pi's default port", 2026-11-13), `nix build .#checks.x86_64-linux.headroom-cli` and `.#checks.x86_64-linux.pi-headroom` failed before reaching any new assertion with:

```
error: Failed to fetch git repository 'ssh://git@github.snooguts.net/reddit/reddit-nix.git'
```

The cause is the check graph, not the change: `headroom-cli`, every `checks/pi*.nix` check, and the work-host extension (`legacyWorkHome`) all evaluate `homeConfigurations.cachyos-framework13`, whose module set pulls the private `reddit-nix` flake input. In an environment without a loaded SSH key (or an SSH agent), that fetch fails regardless of what the diff contains. By contrast, `nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath` succeeds because the razer14 config does not touch that input.

## Guidance

Treat the fetch error as an environment gate, not a regression. Identify which outputs derive from the framework home config (`grep -n 'frameworkHome\|legacyWorkHome' checks.nix`) and split verification in two:

1. Narrow, local, always-runnable evals of the outputs that do not need the private input, plus a direct run of the real packaged artifact. For a Home Manager wrapper change, resolve the exact package derivation and realize it, then run the wrapped binary against a scratch fake in a throwaway `HOME`/`XDG_RUNTIME_DIR`:

   ```bash
   drv=$(nix eval --raw .#nixosConfigurations.razer14.config.home-manager.users.adriel.home.packages \
     --apply 'ps: (builtins.head (builtins.filter (p: (p.pname or "") == "headroom-ai") ps)).drvPath')
   wrapper=$(nix-store -r "$drv" 2>/dev/null | tail -n1)
   ```

   Running the fake through the wrapper proves the same behavior the check asserts (default `--port`, generated `baseURL`, runtime `HEADROOM_PROXY_URL`), so the deferred full check is confirmation, not first coverage.

2. The full `nix build .#checks...` run in CI, or locally with the key loaded (`ssh-add`); state the deferral explicitly in the handoff so it is not silently dropped.

Two small evaluator gotchas from the same session:

- `nix eval --raw` fails with `cannot coerce an integer to a string` on integer-typed options such as `local.headroom.pi.port` (`lib.types.port`); use `--json` and compare against the bare number.
- `--apply` predicates are the cheapest way to assert on a config without a real check derivation, e.g. `--apply 's: builtins.match ".*127\\.0\\.0\\.1:8790.*" (builtins.toJSON s) != null'` over `local.opencode.extraSettings` to pin a generated plugin URL.

## When to Apply

Before blaming a diff for a private-fetch evaluation failure, and whenever a verification plan names checks that evaluate `homeConfigurations.cachyos-framework13`. Keep the substitution narrow: it should exercise the exact production artifact the full check would, so the CI run remains a confirmation step. Do not vendor, stub, or rewrite the private input to make a local run pass; that changes what CI verifies.
