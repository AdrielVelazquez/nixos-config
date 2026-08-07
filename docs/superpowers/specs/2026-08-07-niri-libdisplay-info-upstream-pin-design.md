# Niri libdisplay-info Upstream Pin Design

## Goal

Keep the existing broad `flake.lock` update usable while preserving the
Niri-flake unstable package and configuration module until the upstream
dependency repair merges.

## Target and validation

- Target config: `homeConfigurations.razer14`
- Validation host: `razer14` / NixOS
- Required verification:
  `nix eval .#homeConfigurations.razer14.activationPackage.drvPath`
- Shared-output verification:
  - `nix eval .#checks.x86_64-linux.configuration-contract.drvPath`
  - `nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath`
  - `nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath`
  - `nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath`
- Activation is out of scope. Any `home-manager switch` or
  `nixos-rebuild switch` requires separate explicit approval.

## Root cause

The dirty lock update advances the main Nixpkgs input to
`b7c2ada94fe99c15b0dbcf4d11fd7850b957a436`. That revision contains Nixpkgs
PR #549132, which removed the unused `libdisplay-info_0_2` package.

The locked Niri-flake revision
`9ee3e13b60643448228353097880521658b2fe0e` still requests
`libdisplay-info_0_2` and asserts that its version is `0.2.0`. Its nested Niri
source is already `feb3e43f1475e0865bb89cbd1e898b34d1d2ccf6`, the merge commit
for Niri PR #4366, which migrated Niri to `libdisplay-info_0_3`. Niri-flake's
package expression therefore lags both its Niri source and the followed
Nixpkgs input.

Niri-flake PR #1850 fixes the exact mismatch. Its current head,
`6bb99ff875919f03ea6054026619d999061e1170`, is based directly on the locked
Niri-flake revision and changes the package expression to
`libdisplay-info_0_3`. Evaluating the Razer Home Manager output with that
commit as an input override succeeds.

## Design

Temporarily pin the existing `niri` input to the upstream PR commit through
the official repository:

```nix
niri = {
  url = "github:sodiboo/niri-flake/6bb99ff875919f03ea6054026619d999061e1170";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

Update only the `niri` lock node after changing the declared URL. Preserve
every other existing dirty lock update exactly. Keep both shared module
assignments on `pkgs.niri-unstable`; switching to `pkgs.niri` would avoid the
broken overlay but would also change the selected compositor release and risk
drifting from Niri-flake's generated settings schema.

Add an active `TODO.md` exception describing the original mismatch, upstream
PR and commit, affected outputs, validation commands, and obsolescence check.
The pin becomes obsolete when PR #1850 or an equivalent fix reaches
Niri-flake `main`. At that point, restore `github:sodiboo/niri-flake`, update
only the `niri` input, and remove the TODO after the exact evaluations pass.

## Regression coverage

The existing evaluation failure is the regression test: before the pin,
`homeConfigurations.razer14` fails while evaluating `pkgs.niri-unstable`
because `libdisplay-info_0_2` is removed. The same exact eval passes when the
PR commit is supplied as an input override.

After persisting the pin, run the target eval immediately after each Nix edit.
Then evaluate the configuration contract and all shared Linux Home Manager and
NixOS outputs. Finish with the repository formatter check. No runtime switch or
full CUDA-heavy build is required.

## Scope and ownership

This repair changes only `flake.nix`, the `niri` node in the already modified
`flake.lock`, and `TODO.md`. It does not rewrite, stage, or commit the user's
other lock updates or unrelated untracked files. Because the temporary pin is
an exception to the default upstream input, it must remain visible in
`TODO.md` until removed.
