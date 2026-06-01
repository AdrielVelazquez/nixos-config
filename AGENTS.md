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
  ## Keep flake updates targeted
  - Prefer targeted lock updates such as `nix flake lock --update-input <input>` or the current equivalent command.
  - Do not broad-update `flake.lock` unless explicitly asked.
  - If unrelated lock-file churn appears, call it out before continuing.
  ## Handle new Nix files during eval
  - New files imported by flakes must be added to the Git index before `nix eval`, because flakes ignore untracked files.
  - Stage only the exact new files required for eval. Do not stage unrelated dirty work.
  ## Always validate with eval
  - After every Nix change, run a matching `nix eval` against the exact target output before claiming success.
  - Preferred eval targets:
    NixOS: `nix eval .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`
    Darwin: `nix eval .#darwinConfigurations.<host>.config.system.build.toplevel.drvPath`
    Home Manager: `nix eval .#homeConfigurations.<config>.activationPackage.drvPath`
    system-manager: eval the matching `systemConfigs.<config>` output before running `system-manager switch`
  - When practical, follow eval with the matching dry-run/build/test command. Eval is the minimum bar, not the whole test plan. This might not be pratical for hosts that have cuda or other components that take too long to build
  - For CUDA-heavy or otherwise expensive hosts, exact `nix eval` is acceptable as the minimum validation unless the user asks for a full build.

  ## Avoid Destructive Changes
  - `nix run` or `nixos-switch` are destructive and you should always confirm with user before running it. 
  - Always confirm before commands that change the running system, including `nixos-rebuild switch`, `nixos-rebuild boot`, `home-manager switch`, `darwin-rebuild switch`, `system-manager switch`, and `just switch*`.
  - `nix eval`, targeted `nix flake lock`, and read-only diagnostics are okay without confirmation.
  
  ## Prefer lightweight desktop architecture
  - For Niri and desktop shell changes, prefer small single-purpose services over large resident shells unless explicitly testing an alternative.
  - Before replacing Waybar, Mako, Swaybg, Fuzzel, or similar desktop components, capture current `ps`, `systemd-cgtop`, and GPU/VRAM evidence.
  - New desktop alternatives such as Noctalia should be available as modules but disabled per user/host unless explicitly requested.
  - Do not remove the existing Niri stack when adding an experimental alternative.
  
  ## Keep host-specific config in the right place
  - Keep Razer-specific GPU paths, render-device choices, brightness devices, dGPU behavior, and hardware workarounds in `users/adriel/default.nix` or `hosts/razer14`.
  - Put reusable app, service, and module behavior in `modules/home-manager/*`, `modules/system/*`, or `modules/system-manager/*`.
  
  ## Doing things outside the norm should generate a list of todos to return
  - Sometimes we will make changes that uses a specific commit instead of following unstable (or whatever my default for the flake is). A good example is this commit hash which installed 
    antigravity because it wasn't merged upstream. 3132681a66549d5b7becf24ac3717fa5483666ec 
  - Whenever we make exceptions like above, add it to TODO.md with the reason, upstream link or commit, how to check if it is obsolete, and the target config affected.
  - Review this TODO.md list whenever we make changes. Mostly to see if we can resolve these issues. Let's have this launch as a new subagent 
    to do the research. 
  - When resolving any of the todos, make sure to create a detailed changed. (Detail the original issue, Detail how you resolved it)
  - When resolving TODOs, always try to resolve by getting closer to the default flake input, usually `nixos-unstable`. If a broad exception carries multiple fixes and `nixos-unstable` now has one of them, move that resolved part back to the main input and keep only the still-missing fix as a smaller exception. For example, if something is fixed on a feature branch and later merged into master, use the upstream master commit instead of the feature branch; once it reaches `nixos-unstable`, use the main `nixpkgs` input.
  
  ## Measure performance changes
  - For performance work, capture the current top CPU/RAM/cgroup/GPU state before tuning.
  - After changes, compare the same commands rather than relying on intuition.
  ## Secrets and SOPS
  - When dealing with secrets, always confirm that it won't accidentally end up in the nix store
  - When dealing with anything that might be sensitive information, always prefer to use sops and write to the secrets_enc.yaml file 
