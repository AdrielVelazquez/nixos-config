# Niri epireyn Module Migration Design

## Goal

Replace the stalled `sodiboo/niri-flake` PR pin with the maintained
`epireyn/niri-flake` main branch, compile its pinned `niri-unstable`
derivation locally against the primary Nixpkgs input, keep Xwayland Satellite
on primary Nixpkgs, and refuse the fork's binary cache.

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
- set NixOS and Linux Home Manager `programs.niri.package` assignments to the
  direct `inputs.niri.packages.${pkgs.system}.niri-unstable` derivation;
- retain primary `pkgs.niri` only for the disabled Darwin Home Manager
  consumer because the fork publishes packages for Linux systems only;
- set `niri-flake.cache.enable = false` in the reusable NixOS Niri module;
- replace `pkgs.xwayland-satellite-unstable` with the primary Nixpkgs
  `pkgs.xwayland-satellite`.

The locked primary Nixpkgs currently provides Niri 26.04 and Xwayland
Satellite 0.8.2. The fork's stable Xwayland Satellite input is 0.8.1, alongside
an unstable snapshot, so removing the overlay selects the newer primary
Nixpkgs 0.8.2 package. Niri remains on the historically used development
track: the locked fork package is `unstable-2026-08-14-6062844`, sourced from
upstream `niri-wm/niri` main. Because the fork's `nixpkgs` input follows the
primary input, that package uses the repository's normal Nixpkgs toolchain and
dependencies.

## Trust boundary and fallback

The fork is trusted as pinned, reviewable Nix module, configuration-rendering,
and compositor-package source. Its opaque binary outputs are not trusted. Its
binary cache must not be added to Nix settings, and Xwayland Satellite must
remain on the primary Nixpkgs package set. Evaluation should confirm the cache
option is false, neither the retired `niri.cachix.org` URL/key nor the active
`niri-epireyn.cachix.org` URL/key enters effective Nix settings, and every
Linux consumer selects the direct fork `niri-unstable` derivation without
importing the overlay. The disabled `aarch64-darwin` consumer must select
`pkgs.niri` without enabling a compositor session; this is an evaluation
fallback, not an activated package choice.

Building locally does not eliminate source-level trust: Nix still evaluates
the fork's pinned expressions. It removes trust in binaries signed by the
fork's Cachix key and leaves source changes visible in targeted lock updates.

If `niri-unstable` fails to evaluate or build, stop and report the exact
failure. Do not silently fall back to stable Niri or enable either Niri cache.

## Lock and TODO handling

Run a targeted `nix flake update niri` after changing the declared URL. Keep
all unrelated lock-file revisions intact. The system-manager repair changes
only its locked `nixpkgs` follow relationship; the Niri update changes only the
root Niri node and its nested stable/unstable source nodes.

Replace the active PR-pin TODO with a community-fork exception that records:

- the original display-info failure and closed-unmerged PR;
- why `epireyn/niri-flake` is now used;
- the affected outputs, local-build decision, and cache/package trust
  boundary;
- how to check whether upstream Home Manager plus Nixpkgs can replace the
  fork's remaining structured-module functionality.

Add a resolved-history entry for removing the immutable PR #1850 commit pin.
The fork exception remains active until the structured settings and action
helpers can be sourced from a better-governed upstream without losing the
exact configuration evaluations.

## Atomic commit and rollback

Produce one follow-up commit containing the local-build package selection,
cache-negative contract adjustment, TODO history, and updated design and
implementation plan. Do not include unrelated dirty or untracked work.

Rollback is one `git revert` of that commit. No runtime activation is included,
so reverting affects only the declarative source and lock state until the user
separately switches a configuration.

## Verification

After every Nix edit, evaluate the matching exact output before proceeding.
Finish by verifying:

1. all Home Manager, NixOS, Darwin, and system-manager derivation evaluations return paths;
2. the configuration contract evaluates;
3. every Linux Niri package is the direct fork `niri-unstable` derivation,
   currently `unstable-2026-08-14-6062844`, while disabled Darwin retains the
   primary package fallback;
4. selected Xwayland Satellite packages come from
   `pkgs.xwayland-satellite`;
5. `niri-flake.cache.enable` is false on both NixOS targets;
6. both Niri cache generations and the fork overlay are absent from effective
   settings;
7. formatting and `git diff --check` pass;
8. both rendered Niri configurations build without activation;
9. the direct x86_64-linux `niri-unstable` derivation builds with `--no-link`
   under the existing cache configuration;
10. the staged diff contains only this migration and contract repair.

CUDA-heavy full builds and all activation commands are outside the required
verification scope.
