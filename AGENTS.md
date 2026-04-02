  ## Verify the target first
  - Before making changes, identify the exact target config and the machine/OS required to validate it.
  - Do not assume the edited path name matches the flake output or the machine that must run the verification command.
  - State this explicitly before editing: `Target config: <name>. Validation host: <machine/OS>. Planned verification: <command>.`
  ## Prefer upstream fixes
  - If an issue appears to come from upstream, first check whether it is already fixed upstream.
  - If the repo uses flakes, update the relevant flake input or `flake.lock` first. If the repo does not use flakes, update the channel first.
  - If the fix is not in the pinned version, prefer an upstream PR commit or a commit already merged upstream before writing a local patch.
  - If the repo has its own nixpkgs fork, ask whether the change should be made there and consumed by commit hash instead of patching locally.
  - Only write a local patch when those options fail. Keep it minimal and put it in a separate file named `{package}-path-{fix-reason}.nix`.
  ## Always validate with eval
  - After every Nix change, run a matching `nix eval` against the exact target output before claiming success.
  - Preferred eval targets:
    NixOS: `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
    Darwin: `nix eval .#darwinConfigurations.<host>.config.system.build.toplevel.drvPath`
    Home Manager: `nix eval .#homeConfigurations.<config>.activationPackage.drvPath`
    system-manager: eval the matching `systemConfigs.<config>` output before running `system-manager switch`
  - When practical, follow eval with the matching dry-run/build/test command. Eval is the minimum bar, not the whole test plan.

  ## Avoid Destructive Changes
  - `nix run` or `nixos-switch` are destructive and you should always confirm with user before running it. 
