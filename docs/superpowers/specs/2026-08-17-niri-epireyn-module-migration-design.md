# Niri epireyn Module Migration Design

## Goal

Replace the stalled `sodiboo/niri-flake` PR pin with the maintained
`epireyn/niri-flake` main branch while keeping Niri and Xwayland Satellite
packages on the primary Nixpkgs input and refusing the fork's binary cache.

## Target and validation

- Target configs:
  - `homeConfigurations.razer14`
  - `homeConfigurations.cachyos-framework13`
  - `nixosConfigurations.razer14`
  - `nixosConfigurations.dell-plex`
  - `darwinConfigurations.PNH46YXX3Y`
  - `systemConfigs.cachyos-framework13`
  - `checks.x86_64-linux.configuration-contract`
- Validation host: current x86_64 NixOS 26.11 machine.
- Minimum verification:
  - `nix eval .#homeConfigurations.razer14.activationPackage.drvPath`
  - `nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath`
  - `nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath`
  - `nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath`
  - `nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath`
  - `nix eval .#systemConfigs.cachyos-framework13.drvPath`
  - `nix eval .#checks.x86_64-linux.configuration-contract.drvPath`
- Activation is out of scope. Any switch command requires separate approval.

## Current state and reason for migration

The original `sodiboo/niri-flake` main branch remains at
`9ee3e13b60643448228353097880521658b2fe0e` with a removed
`libdisplay-info_0_2` dependency. PR #1850 supplied a temporary repair at
`6bb99ff875919f03ea6054026619d999061e1170`, but the PR closed without merging
and issue #1851 remains open.

The `epireyn/niri-flake` fork was created to continue maintaining the module.
Its main branch fixes the display-info dependency, updates stable Niri to
26.04, follows the current `niri-wm/niri` repository, and preserves the
`nixosModules.niri`, `homeModules.niri`, structured `programs.niri.settings`,
and `config.lib.niri.actions` interfaces used by this repository. Exact input
overrides to fork main already evaluated successfully for the four Home
Manager and NixOS outputs.

## Design

Before the Niri migration, restore the existing system-manager contract. The
current system-manager adapter requires NixOS options that are absent from the
pinned Fleet nixpkgs revision. Make system-manager follow primary Nixpkgs and
pass a configuration-local overlay containing only `fleet-orbit` and
`fleet-desktop` from `nixpkgs-fleet`. This returns system-manager, Mesa, and all
unrelated Framework packages to the primary package set without dropping the
still-required Fleet exception.

Keep the existing input name and make it follow fork main:

```nix
niri = {
  url = "github:epireyn/niri-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Continue importing the fork's NixOS and Home Manager modules so the existing
structured configuration does not require a KDL rewrite. Do not use its
package overlay or Cachix cache:

- remove `inputs.niri.overlays.niri` from standalone and embedded Home Manager
  package sets;
- set both system and Home Manager `programs.niri.package` assignments to
  `pkgs.niri`;
- set `niri-flake.cache.enable = false` in the reusable NixOS Niri module;
- replace `pkgs.xwayland-satellite-unstable` with the primary Nixpkgs
  `pkgs.xwayland-satellite`.

The locked primary Nixpkgs currently provides Niri 26.04 and Xwayland
Satellite 0.8.2. The fork overlay also currently exposes Xwayland Satellite
0.8.2, so removing the overlay does not downgrade that package. Niri moves
from a git snapshot to the supported 26.04 release by explicit user choice.

## Trust boundary and fallback

The fork is trusted only as evaluated Nix module and configuration-rendering
source. Its binary cache must not be added to Nix settings, and its compositor
or satellite derivations must not be selected. Evaluation should confirm the
cache option is false and both selected packages come from the primary
Nixpkgs package set.

If `pkgs.niri` proves incompatible with the structured settings or runtime,
stop and report the exact failure. Re-enabling the fork cache is an available
rollback, but it is not part of this migration and must not happen silently.

## Lock and TODO handling

Run a targeted `nix flake update niri` after changing the declared URL. Keep
all unrelated lock-file revisions intact. The system-manager repair changes
only its locked `nixpkgs` follow relationship; the Niri update changes only the
root Niri node and its nested stable/unstable source nodes.

Replace the active PR-pin TODO with a community-fork exception that records:

- the original display-info failure and closed-unmerged PR;
- why `epireyn/niri-flake` is now used;
- the affected outputs and cache/package trust boundary;
- how to check whether upstream Home Manager plus Nixpkgs can replace the
  fork's remaining structured-module functionality.

Add a resolved-history entry for removing the immutable PR #1850 commit pin.
The fork exception remains active until the structured settings and action
helpers can be sourced from a better-governed upstream without losing the
exact configuration evaluations.

## Atomic commit and rollback

Produce exactly one commit containing the input declaration, targeted Niri
lock changes, package/cache decoupling, TODO history, design and implementation
plan, and any required contract adjustment. Do not include unrelated dirty or
untracked work.

Rollback is one `git revert` of that commit. No runtime activation is included,
so reverting affects only the declarative source and lock state until the user
separately switches a configuration.

## Verification

After every Nix edit, evaluate the matching exact output before proceeding.
Finish by verifying:

1. all Home Manager, NixOS, Darwin, and system-manager derivation evaluations return paths;
2. the configuration contract evaluates;
3. selected Niri versions are 26.04 from `pkgs.niri`;
4. selected Xwayland Satellite packages come from
   `pkgs.xwayland-satellite`;
5. `niri-flake.cache.enable` is false on both NixOS targets;
6. the fork overlay and `niri-unstable` package references are absent;
7. formatting and `git diff --check` pass;
8. both rendered Niri configurations build without activation;
9. the staged diff contains only this migration and contract repair.

CUDA-heavy full builds and all activation commands are outside the required
verification scope.
