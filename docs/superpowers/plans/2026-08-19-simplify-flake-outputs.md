# Simplify Flake Outputs Implementation Plan

Date: 2026-08-19

## Objective

Replace the repository's direct `flake-parts` architecture with explicit flake
outputs, then retire Dell, macOS, and standalone Razer Home Manager in a second
commit that can be reverted independently from the final branch.

The active runtime boundaries remain:

- `nixosConfigurations.razer14`, with embedded Home Manager and activation via
  `just switch razer14`.
- `homeConfigurations.cachyos-framework13`, activated separately.
- `systemConfigs.cachyos-framework13`, activated separately.

No switch or activation command is part of implementation verification.

## Commit 1: Replace flake-parts with direct outputs

Start from `main` while every pre-retirement implementation still exists.

### Flake structure

- Remove only the repository's direct `flake-parts` input.
- Define the following outputs directly in `flake.nix`:
  - `nixosConfigurations.razer14`
  - `nixosConfigurations.dell-plex`
  - `darwinConfigurations.PNH46YXX3Y`
  - `homeConfigurations.razer14`
  - `homeConfigurations.cachyos-framework13`
  - `systemConfigs.cachyos-framework13`
  - `apps.x86_64-linux.system-manager`
  - Linux and Darwin formatters
  - Linux and Darwin checks, including the six shared checks plus `reddit-mac`
    on `aarch64-darwin`
- Preserve module order, special arguments, Home Manager integration,
  standalone Razer CUDA capabilities, Darwin Homebrew taps, Framework Fleet
  isolation, Mesa ownership, and the official upstream Niri package.
- Move the checks module to root `checks.nix` and pass outputs and dependencies
  explicitly. Remove all `config.flake`, `perSystem`, and flake-module
  indirection.
- Delete `parts/` after its behavior is represented directly.

### Lock boundary

The first lock diff may only:

- remove the direct `flake-parts` revision
  `427bf4bd9435fdf21321c8cc628c24efc14c0f7a`;
- normalize the remaining System Manager/userborn `flake-parts` node label;
- retain that transitive revision at
  `80daad04eddbbf5a4d883996a73f3f542fa437ac`.

No surviving revision or hash may change.

### Commit 1 verification

Stage newly imported Nix files before flake evaluation, then run:

```bash
rtk nix eval --raw --no-write-lock-file .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval --raw --no-write-lock-file .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval --raw --no-write-lock-file .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval --raw --no-write-lock-file .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval --raw --no-write-lock-file .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval --raw --no-write-lock-file .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval --json --no-write-lock-file .#checks.aarch64-darwin --apply 'checks: builtins.attrNames checks'
rtk just check
rtk just check-fast
rtk git diff --cached --check
```

Confirm exact output names, including the baseline Darwin check set
`[configuration-contract, justfile-contract, lua-format, nix-format,
nvim-regressions, reddit-mac, shell-syntax]`, and compare active derivations
with the baseline.
System Manager must remain byte-identical. Razer and Framework Home Manager
may differ only through the repository source-store prefix embedded in the
unchanged wallpaper and out-of-store-link paths, as demonstrated by
`nix-diff`.

Commit as:

```text
Replace flake-parts with direct outputs
```

## Commit 2: Remove retired Dell and macOS configurations

Perform retirement only after the explicit architecture is committed.

### Remove output wiring and exclusive code

- Remove `nixosConfigurations.dell-plex`.
- Remove `darwinConfigurations.PNH46YXX3Y` and the top-level Darwin output.
- Remove standalone `homeConfigurations.razer14`; retain embedded Razer Home
  Manager unchanged.
- Remove retired output derivations and semantic assertions from `checks.nix`.
- Remove Darwin recipes and retired-output expectations from the Justfile and
  its contract test.
- Delete the retired host, user, service, and profile files proven unreachable
  from Razer and Framework.
- Update README topology and live TODO consumer text. Preserve resolved TODO
  history verbatim.

### Remove exclusive dependencies

- Remove `nix-darwin`, `nix-homebrew`, `homebrew-core`, `homebrew-cask`, and
  `homebrew-bundle` from `flake.nix`.
- Prune only their now-unreachable lock nodes.
- Keep `reddit`, because Framework Home Manager still uses its overlay.

### Commit 2 verification

Run exact evals for the three surviving configurations, confirm their output
name sets are exact, then run `rtk just check`, `rtk just check-fast`, lock and
removed-reference audits, formatting, and `rtk git diff --cached --check`.

Commit as:

```text
Remove retired Dell and macOS configurations
```

## Rollback proof

From final HEAD, create a temporary detached worktree and run an actual
no-commit revert of the retirement commit. It must apply without conflicts.
In that reverted tree:

- confirm Dell, Reddit Mac, and standalone Razer Home Manager output names are
  restored;
- confirm the complete seven-name `checks.aarch64-darwin` set is restored;
- evaluate their exact derivation targets;
- confirm explicit output wiring remains and `flake-parts` does not return.

Abort the temporary revert and remove only that temporary worktree. The feature
worktree and final branch remain intact.

## Final review

- Confirm the worktree is clean and exactly two commits sit above `main` in the
  order documented here.
- Run a read-only code review over `main..HEAD`.
- Fix every Critical or Important finding before offering merge, PR, or
  keep-branch integration choices.
