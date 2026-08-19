# Simplify Flake Outputs Design

Date: 2026-08-19

## Context

This repository now manages two active machines:

- `razer14`, which runs NixOS and activates its Home Manager configuration as
  part of `nixos-rebuild switch`.
- `cachyos-framework13`, which runs CachyOS and deliberately keeps System
  Manager and standalone Home Manager as separate activation boundaries.

The `dell-plex` NixOS host and `PNH46YXX3Y` Reddit Mac are retired. If either
use case returns, it will be implemented from scratch instead of preserving the
old configuration as a template. The standalone `homeConfigurations.razer14`
output is also redundant because Razer is always activated through its NixOS
output.

The current flake uses `flake-parts` to distribute output construction across
seven files under `parts/`. This adds a system matrix, flake-module arguments,
`config.flake.*` indirection, and generalized host constructors even though all
remaining outputs target `x86_64-linux`. The abstraction makes the complete
active topology harder to see and makes host changes require edits across
multiple registries and contracts.

## Goals

- Make all active outputs visible from `flake.nix` without a flake-module
  framework.
- Preserve the current Razer and Framework activation boundaries and behavior.
- Remove retired host implementations and dependencies rather than carrying
  speculative scaffolding.
- Keep reusable NixOS, Home Manager, and System Manager behavior in the existing
  `modules/` hierarchy.
- Retain strong checks for the active configurations while removing contracts
  that exist only to validate retired outputs or generalized registries.
- Produce a Git history in which the explicit-output refactor lands first and
  retired-host removal is a later, independently revertible decision.

## Non-goals

- Changing packages, services, Niri settings, secrets, or activation behavior
  on either active host.
- Combining Framework System Manager and Home Manager activation.
- Adding a new host-constructor framework for possible future machines.
- Updating dependency revisions beyond lock nodes necessarily removed from the
  input graph.
- Activating any configuration during implementation or verification.

## Final output topology

`flake.nix` will directly expose:

```text
nixosConfigurations.razer14
homeConfigurations.cachyos-framework13
systemConfigs.cachyos-framework13
apps.x86_64-linux.system-manager
checks.x86_64-linux
formatter.x86_64-linux
```

There will be no `darwinConfigurations`, `dell-plex` output, standalone Razer
Home Manager output, `systems` matrix, `perSystem`, or `config.flake.*`
indirection.

The output expression may use local values for facts shared by the active
outputs, including `system = "x86_64-linux"`, `specialArgs`, the official Niri
package, Home Manager integration settings, and the Framework Fleet overlay.
These values are implementation details of the explicit outputs, not a public
host-registration API.

## Retired-host cleanup

The second implementation commit will remove the retired branches from the
already-explicit output architecture:

- Delete `hosts/dell-plex-server/`, `hosts/reddit-mac/`,
  `users/adriel-dell/`, `users/adriel.velazquez/`, and
  `modules/mac-services/`.
- Remove `dell-plex`, `PNH46YXX3Y`, and standalone Razer Home Manager outputs.
- Remove `nix-darwin`, `nix-homebrew`, `homebrew-core`, `homebrew-cask`, and
  `homebrew-bundle` inputs.
- Remove Darwin recipes and retired-host names from the Justfile and README.
- Remove modules that are proven to belong only to the retired Dell or macOS
  lineages and are unreachable from both active configurations.
- Remove checks for retired outputs while retaining active Framework and Razer
  contracts.

The `reddit` input remains because the Framework Home Manager output uses its
overlay. Resolved entries in `TODO.md` retain historical output names and paths
because they describe the repository at the time of each resolution. Only live
active-TODO text is updated to name surviving consumers accurately.

## Direct-output refactor

The first implementation commit will:

- Replace `flake-parts.lib.mkFlake` with a normal flake output attribute set.
- Move shared constants and every existing output from `parts/` into explicit
  `flake.nix` bindings, including the outputs retired by the following commit.
- Convert the checks into an ordinary imported Nix function rather than a
  flake-parts module.
- Remove the `flake-parts` input and the remaining `parts/` directory.
- Keep the System Manager CLI app under `x86_64-linux` and preserve formatter
  and configuration outputs for both existing platforms.
- Preserve the complete check matrix: the shared format, syntax, regression,
  Justfile, and configuration contracts on both platforms; Linux-only service
  checks on Linux; and the `reddit-mac` system check on Darwin.
- Update live documentation and the System Manager graphics TODO path to the
  final direct owner.

The checks implementation may remain in one focused file unless splitting it
is required for clarity. It must receive explicit dependencies rather than
discovering outputs through `config.flake`.

## Dependency and lock policy

Lock changes are structural only. The first commit removes this repository's
direct `flake-parts` input and its `427bf4bd` lock node. The second removes lock
nodes made unreachable by retiring Darwin/Homebrew inputs. A separate
transitive `flake-parts` instance at `80daad04` remains owned by System Manager's
`userborn` input and is not part of this refactor; Nix may normalize that
survivor's node label after the direct node disappears. Revisions and hashes
for every surviving input must remain unchanged. Any unrelated lock churn
stops the change for investigation.

## Behavior-preservation contract

Before editing, the active baseline derivations are:

```text
razer:
  /nix/store/il2jlmzhx9wby4rql9gz59i7gvq2d8q4-nixos-system-razer14-26.11.20260818.0ae2bc1.drv
framework Home Manager:
  /nix/store/ql5hqmp76j61rxapl1z7c6mpvxqfiy17-home-manager-generation.drv
framework System Manager:
  /nix/store/ykj7ml5cm1bnqbmsp3vwxy96c5hc0vzh-system-manager.drv
```

These paths are the diagnostic comparison points, but only System Manager can
remain byte-identical. Both Home Manager configurations intentionally refer to
repository-relative wallpaper and out-of-store-link paths. Any Git-tree change
therefore gives the flake source a new store identity and changes the Razer and
Framework Home Manager derivations even when their evaluated behavior is
unchanged. Each mismatch must be traced with `nix-diff`: acceptable differences
are limited to that repository source-store prefix, while referenced asset
content and every configuration contract remain unchanged. Existing contracts
for the selected Niri package, Framework-native packages, Fleet isolation,
Mesa paths, portal ownership, and session-safe service behavior remain in
force.

## Verification

At the baseline and after each implementation commit:

1. Evaluate the exact Razer NixOS toplevel derivation path.
2. Evaluate the exact Framework Home Manager activation derivation path.
3. Evaluate the exact Framework System Manager derivation path.
4. Compare System Manager directly with its baseline and use `nix-diff` for
   Razer and Framework Home Manager, allowing only the explained repository
   source-store identity change.
5. Run the focused configuration contracts and `just check`.
6. Run formatting and `git diff --check`.
7. Confirm removed output names, retired paths, and `flake-parts` references are
   absent from live configuration and documentation.
8. Audit the lock diff to prove surviving input revisions did not change.
9. At the first commit, additionally evaluate Dell NixOS, standalone Razer Home
   Manager, and Reddit Mac, and assert that `checks.aarch64-darwin` contains
   `configuration-contract`, `justfile-contract`, `lua-format`, `nix-format`,
   `nvim-regressions`, `reddit-mac`, and `shell-syntax`, so the later retirement
   revert has a known-good restoration point.
10. At final HEAD, perform an actual no-commit revert of the retirement commit
    in a temporary worktree, evaluate the restored output topology, then abort
    and remove the temporary worktree.

CUDA-heavy Razer verification stops at exact evaluation unless a later request
explicitly asks for its full build. No `switch`, activation, or other running
system mutation is part of this work.

## Commit and rollback strategy

The final feature history contains two ordered commits:

1. `Replace flake-parts with direct outputs`
2. `Remove retired Dell and macOS configurations`

Reverting the second commit restores the retired host implementations,
dependencies, explicit outputs, and checks while retaining the simpler direct
flake architecture. Reverting the first commit is only necessary if the
repository itself should return to flake-parts.

## Adding a future host

A future host begins with a new host directory and one explicit output in
`flake.nix`. Shared behavior moves into `modules/` only when the new host
actually shares it. A generalized constructor or output registry is introduced
only after repeated active configurations demonstrate that the abstraction is
smaller and clearer than their explicit definitions.
