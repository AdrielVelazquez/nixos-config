---
title: In a flake, drvPath equality cannot prove a refactor is behavior-neutral - compare evaluated option values instead
date: 2026-10-23
category: tooling-decisions
module: flake.nix
problem_type: workflow_issue
component: tooling
severity: low
applies_when:
  - "Moving Nix options between files and wanting proof that a host's configuration did not change"
  - "A before/after nix eval of activationPackage.drvPath or toplevel.drvPath differs after a pure move"
  - "Another person or agent is editing the same checkout while you work"
tags: [nix, flakes, drvpath, refactor, verification, home-manager]
last_updated: 2026-10-23
---

# In a flake, drvPath equality cannot prove a refactor is behavior-neutral - compare evaluated option values instead

## Context
Moving shared Pi settings from `users/adriel-cachyos/default.nix` into a shared module looked like it should leave Framework's `activationPackage.drvPath` identical. It changed. `nix-diff` showed only source-path churn, for example `hm_oona.jpg` moving between two `...-source/modules/home-manager/oona.jpg` store paths.

## Guidance
- In a flake, every relative path literal that is interpolated resolves under the single `...-source` store path of the whole tree. Any tracked-file edit therefore changes that path and every derivation that references one, so the hash differs even when no option changed. `drvPath` equality is not a usable test for "pure move".
- Instead evaluate the options the move could touch, normalize `/nix/store/<hash>-` to a fixed token, sort the JSON, and diff the committed state against the working tree. Evaluate the committed side with `nix eval 'git+file:///path/to/repo?rev=<sha>#...'`.
- Keep that comparison honest in a shared checkout: diff the whole option tree, then explain each surviving line. Here the only difference was a `model-hint.ts` extension someone else had added to `modules/home-manager/pi.nix` mid-session, which the comparison excluded by name rather than hiding.

## Why This Matters
The failure is silent in the other direction too: a drv hash that happens to match would prove nothing about values, and a mismatch sends you hunting for a change you did not make.

## When to Apply
- Before promising "no behavior change" for a Nix refactor in this repo.
- After any evaluation difference that tracks edits unrelated to the option you moved.

## Related
- `docs/solutions/tooling-decisions/pi-builtin-providers-through-headroom.md`
