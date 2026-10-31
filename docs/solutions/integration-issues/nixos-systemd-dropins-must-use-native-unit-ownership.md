---
title: NixOS systemd drop-ins must use native unit ownership, not nested environment.etc entries
date: 2026-10-31
category: integration-issues
module: modules/system/endpoint-agent-limits.nix
problem_type: integration_issue
component: infrastructure
symptoms:
  - "Native host evaluation succeeds, but the etc derivation fails with permission denied creating duo-desktop.service.d"
  - "A resource-limit module imports cleanly from system-manager into NixOS"
root_cause: config_error
resolution_type: config_change
severity: medium
tags: [nix, nixos, systemd, system-manager, dropins, checks]
---

# NixOS systemd drop-ins must use native unit ownership

## Problem

The Framework NixOS migration initially reused the system-manager endpoint-limit
modules because they contained ordinary systemd drop-ins. Exact host evaluation
passed. The full build failed while creating a directory beneath the generated
`/etc/systemd/system` tree; no activation was needed to expose the error.

## Root cause

On the evaluated pins, NixOS owns that entire directory as a link to its generated
unit tree. The system-manager modules instead declare individual nested
`environment.etc` files. Combining those ownership models makes the etc builder
try to create children through a store-backed symlink. This is not a missing
runtime permission, and changing permissions or running the build as root is not
the solution. Matching Nix option types did not establish module portability.

## Solution

Keep the CachyOS modules unchanged. The NixOS counterpart uses normal
`systemd.services` resource settings for installed Orbit/WARP services, and
`systemd.units` with `overrideStrategy = "asDropin"` for vendor agents that are
not installed yet. User-unit limits use `systemd.user.units`.

See `modules/system/endpoint-agent-limits.nix:18` and
`modules/system/endpoint-agent-limits.nix:44`. Explicit drop-in strategy matters:
it preserves limits without synthesizing a main Falcon/Duo service that could
misrepresent an undeployed endpoint agent.

## Verification and prevention

The reproducing contract failed on the original permission error, then passed
alongside the full host build after the native conversion. The contract now
realizes the actual etc derivation and checks that vendor drop-in directories
exist while their main services do not (`checks/framework-work.nix:108`).

When reusing system-manager modules on NixOS, audit generated-file ownership,
not just imports and option schemas. Build the owning artifact after evaluation:

```bash
nix build --no-link .#checks.x86_64-linux.framework-work-contract
```

A drvPath-only eval cannot catch a collision that occurs when the etc builder
assembles its symlinks and directories.
