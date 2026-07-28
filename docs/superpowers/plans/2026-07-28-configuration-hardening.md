# Configuration Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete the approved strict naming cutover, make every generic operational recipe require an explicit target, remove automatic native Orbit package removal, restore normal Nix defaults, and scope CUDA `llama-cpp` to the Razer host.

**Architecture:** Flake output names are the canonical host interface and the `justfile` renders only explicit targets. Evaluated Nix assertions protect cross-host policy, while a real `just --dry-run` shell test protects command behavior without activating anything. Host ownership remains declarative: system-manager detects native Orbit conflicts, and a separate interactive recipe performs the one-time migration.

**Tech Stack:** Nix flakes and flake-parts, NixOS, Home Manager, nix-darwin, system-manager, Bash, and Just.

## Global Constraints

- Target configs are `nixosConfigurations.razer14`, `nixosConfigurations.dell-plex`, `homeConfigurations.razer14`, `homeConfigurations.cachyos-framework13`, `systemConfigs.cachyos-framework13`, and `darwinConfigurations.PNH46YXX3Y`.
- Validation host is `framework13` running CachyOS Linux; NixOS and Darwin targets are evaluated but never activated here.
- The cutover keeps no `default`, `dell`, `adriel`, or `cachyos-framework` compatibility aliases.
- Generic NixOS, Home Manager, Darwin, and system-manager recipes require an explicit target.
- System-manager must never invoke native package removal during activation or boot.
- `just migrate-cachyos-orbit` is interactive and must not use `--noconfirm`.
- Framework Nix trust uses the effective root-only default.
- Root Nix maintenance invokes binaries below `/nix/var/nix/profiles/default/bin` instead of forwarding the caller's `PATH`.
- CUDA `llama-cpp` belongs only to the Razer user wrapper, with `cudaCapabilities = [ "12.0" ]` and `CMAKE_CUDA_ARCHITECTURES=120`.
- Endpoint-agent CPU and memory limits remain unchanged.
- The existing uncommitted `flake.lock` belongs to the user: do not edit, stage, or commit it.
- Every Nix edit is followed by an exact affected-output `nix eval`; new files referenced by the flake are staged before evaluation.
- No `nixos-rebuild switch`, Home Manager switch, system-manager switch, Darwin switch, `just switch*`, `pacman`, service restart, or other activation command may run.

---

### Task 1: Canonical outputs and explicit command targets

**Files:**

- Create: `tests/justfile-contract.sh`
- Modify: `parts/checks.nix`
- Modify: `parts/nixos.nix`
- Modify: `parts/home-manager.nix`
- Modify: `parts/system-manager.nix`
- Modify: `justfile`
- Modify: `modules/system-manager/bolt.nix`
- Modify: `modules/system-manager/niri.nix`
- Modify: `README.md`
- Modify: `hosts/cachyos-framework13-system-manager/README.md`

**Interfaces:**

- Consumes: the current flake output sets and Just recipes.
- Produces: the six canonical output names, required target parameters, and the `checks.x86_64-linux.justfile-contract` derivation used by later tasks.

- [ ] **Step 1: Add failing output-name assertions**

Add these derived names near the top of `parts/checks.nix`:

```nix
  nixosOutputNames = builtins.attrNames config.flake.nixosConfigurations;
  homeOutputNames = builtins.attrNames config.flake.homeConfigurations;
  systemOutputNames = builtins.attrNames config.flake.systemConfigs;
```

Add these entries to the `configurationContract` assertion list:

```nix
          {
            assertion = nixosOutputNames == [
              "dell-plex"
              "razer14"
            ];
            message = "NixOS outputs must use the canonical dell-plex and razer14 names";
          }
          {
            assertion = homeOutputNames == [
              "cachyos-framework13"
              "razer14"
            ];
            message = "Home Manager outputs must use canonical host names";
          }
          {
            assertion = systemOutputNames == [ "cachyos-framework13" ];
            message = "system-manager must expose only cachyos-framework13";
          }
```

- [ ] **Step 2: Add the failing real Just behavior test**

Create `tests/justfile-contract.sh` with Bash helpers that:

```bash
#!/usr/bin/env bash
set -euo pipefail

repo_root=${1:?usage: justfile-contract.sh REPOSITORY}
cd "$repo_root"

expect_missing_target() {
  local recipe=$1
  if just --dry-run "$recipe" >/dev/null 2>&1; then
    echo "Expected '$recipe' to reject a missing target" >&2
    exit 1
  fi
}

expect_rendered() {
  local expected=$1
  shift
  local output
  output=$(just --dry-run "$@")
  case "$output" in
    *"$expected"*) ;;
    *)
      echo "Expected 'just --dry-run $*' to contain: $expected" >&2
      echo "$output" >&2
      exit 1
      ;;
  esac
}

just --list >/dev/null

for recipe in \
  switch switch-trace build test dry-run diff \
  home-switch home-build \
  darwin-switch darwin-build \
  system-manager-switch
do
  expect_missing_target "$recipe"
done

expect_rendered "--flake .#razer14" switch razer14
expect_rendered "--flake .#razer14 --show-trace" switch-trace razer14
expect_rendered "--flake .#dell-plex" build dell-plex
expect_rendered "--flake .#razer14" test razer14
expect_rendered "--flake .#razer14" dry-run razer14
expect_rendered "--flake .#dell-plex" diff dell-plex
expect_rendered "--flake .#razer14" home-switch razer14
expect_rendered "--flake .#cachyos-framework13" home-build cachyos-framework13
expect_rendered "--flake .#PNH46YXX3Y" darwin-switch PNH46YXX3Y
expect_rendered "--flake .#PNH46YXX3Y" darwin-build PNH46YXX3Y
expect_rendered "--flake '.#cachyos-framework13'" system-manager-switch cachyos-framework13
expect_rendered "homeConfigurations.cachyos-framework13.activationPackage" home-activate-cachyos
expect_rendered "--flake '.#cachyos-framework13'" bootstrap-cachyos
```

Wire it into `parts/checks.nix`:

```nix
        justfile-contract =
          pkgs.runCommand "justfile-contract"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.just
              ];
            }
            ''
              bash "${src}/tests/justfile-contract.sh" "${src}"
              touch "$out"
            '';
```

- [ ] **Step 3: Stage the new test and prove both contracts fail for the intended reason**

Run:

```bash
rtk git add tests/justfile-contract.sh
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk bash tests/justfile-contract.sh .
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
```

Expected: the exact Razer eval succeeds; the Bash test reports that `switch`
accepts a missing target; the configuration contract reports the noncanonical
output sets.

- [ ] **Step 4: Rename the flake outputs and checks**

Make these exact output changes:

```nix
# parts/nixos.nix
dell-plex = mkNixosConfig {
  profile = "desktop";
  hostConfig = ../hosts/dell-plex-server/configuration.nix;
  userConfig = ../users/adriel-dell;
};

# parts/home-manager.nix
razer14 = mkHomeConfig {
  userConfig = ../users/adriel;
};

# parts/system-manager.nix
cachyos-framework13 =
  mkSystemConfig ../hosts/cachyos-framework13-system-manager/configuration.nix;
```

Update `parts/checks.nix` consumers and flake check names:

```nix
frameworkSystem = config.flake.systemConfigs.cachyos-framework13.config;
razerHomeOutput = config.flake.homeConfigurations.razer14;

dell-plex = config.flake.nixosConfigurations.dell-plex.config.system.build.toplevel;
home-razer14 = config.flake.homeConfigurations.razer14.activationPackage;
system-cachyos-framework13 = config.flake.systemConfigs.cachyos-framework13;
```

Do not retain the old attributes.

- [ ] **Step 5: Make every generic recipe require its target**

Remove the `=""` or named default from the affected Just parameters and render
the target directly. The NixOS recipes use this shape:

```just
switch hostname:
    {{inhibit}} sudo nixos-rebuild switch --flake .#{{hostname}}

switch-trace hostname:
    {{inhibit}} sudo nixos-rebuild switch --flake .#{{hostname}} --show-trace

build hostname:
    {{inhibit}} nixos-rebuild build --flake .#{{hostname}}

test hostname:
    {{inhibit}} sudo nixos-rebuild test --flake .#{{hostname}}

dry-run hostname:
    {{inhibit}} nixos-rebuild dry-build --flake .#{{hostname}}

diff hostname:
    {{inhibit}} nixos-rebuild build --flake .#{{hostname}} && nvd diff /run/current-system result
```

Apply the same required-argument form to `home-switch`, `home-build`,
`darwin-switch`, `darwin-build`, and `system-manager-switch`. Update the
Framework convenience recipe and fallback host listings to the canonical names.

- [ ] **Step 6: Update live guidance for the new names**

Update both READMEs and the pre-activation error messages in
`modules/system-manager/{bolt,niri}.nix`. Command examples must use:

```text
.#dell-plex
.#razer14
.#cachyos-framework13
```

Change bracketed optional arguments such as `[host]` to required placeholders
such as `HOST`.

- [ ] **Step 7: Run exact evals and the green contracts**

Run:

```bash
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk bash tests/justfile-contract.sh .
rtk nix build .#checks.x86_64-linux.configuration-contract .#checks.x86_64-linux.justfile-contract --no-link
```

Expected: all commands exit 0; the existing `mesa.drivers` warning may remain.

- [ ] **Step 8: Commit the canonical cutover**

```bash
rtk git add tests/justfile-contract.sh parts/checks.nix parts/nixos.nix parts/home-manager.nix parts/system-manager.nix justfile modules/system-manager/bolt.nix modules/system-manager/niri.nix README.md hosts/cachyos-framework13-system-manager/README.md
rtk git diff --cached --check
rtk git commit -m "refactor: use canonical configuration targets"
```

---

### Task 2: Explicit Orbit ownership migration

**Files:**

- Modify: `parts/checks.nix`
- Modify: `tests/justfile-contract.sh`
- Modify: `modules/system-manager/orbit.nix`
- Modify: `justfile`
- Modify: `hosts/cachyos-framework13-system-manager/README.md`

**Interfaces:**

- Consumes: `local.orbit.archPackageNames` and system-manager pre-activation assertions.
- Produces: `orbitNativePackageConflict`, a nonmutating activation gate, and the explicit `migrate-cachyos-orbit` recipe.

- [ ] **Step 1: Add failing Orbit ownership assertions**

Add to `configurationContract`:

```nix
          {
            assertion = !(frameworkServices ? remove-native-orbit);
            message = "system-manager must not remove native Orbit from a boot service";
          }
          {
            assertion = frameworkAssertions.orbitNativePackageConflict.enable or false;
            message = "Orbit must reject native Fleet package conflicts before activation";
          }
          {
            assertion =
              lib.hasInfix "/usr/bin/pacman -Q"
                (frameworkAssertions.orbitNativePackageConflict.script or "")
              && lib.hasInfix "just migrate-cachyos-orbit"
                (frameworkAssertions.orbitNativePackageConflict.script or "");
            message = "the Orbit conflict assertion must identify the explicit migration";
          }
```

Extend `tests/justfile-contract.sh`:

```bash
orbit_migration=$(just --dry-run migrate-cachyos-orbit)
case "$orbit_migration" in
  *"/usr/bin/pacman -R"*) ;;
  *) echo "Orbit migration must render native package removal" >&2; exit 1 ;;
esac
case "$orbit_migration" in
  *"--noconfirm"*) echo "Orbit migration must remain interactive" >&2; exit 1 ;;
esac

bootstrap_output=$(just --dry-run bootstrap-cachyos)
case "$bootstrap_output" in
  *"/usr/bin/pacman -R"*)
    echo "Framework bootstrap must not migrate Orbit implicitly" >&2
    exit 1
    ;;
esac
```

- [ ] **Step 2: Prove the Orbit tests fail before implementation**

Run:

```bash
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk bash tests/justfile-contract.sh .
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
```

Expected: the exact system-manager eval succeeds; the Bash test reports the
missing migration recipe; the contract reports the existing removal unit and
missing pre-activation assertion.

- [ ] **Step 3: Replace automatic removal with a pre-activation assertion**

In `modules/system-manager/orbit.nix`, delete `removeNativeOrbit`, the
`removeNativePackage` option, `systemd.services.remove-native-orbit`, and the
Orbit unit's conditional ordering on that service.

Retain `archPackageNames`, but change its description to identify native package
conflicts. Add:

```nix
    system-manager.preActivationAssertions.orbitNativePackageConflict = {
      enable = true;
      script = ''
        if [ ! -x /usr/bin/pacman ]; then
          echo "Cannot verify native Fleet packages because /usr/bin/pacman is unavailable."
          exit 1
        fi

        conflict=0
        for package in ${lib.escapeShellArgs cfg.archPackageNames}; do
          if /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
            echo "Native Fleet package conflicts with Nix-managed Orbit: $package"
            conflict=1
          fi
        done

        if [ "$conflict" -ne 0 ]; then
          echo "Run 'just migrate-cachyos-orbit' and approve the package removal before activating systemConfigs.cachyos-framework13."
          exit 1
        fi
      '';
    };
```

- [ ] **Step 4: Add the interactive one-time migration recipe**

Add to the system-manager section of `justfile`:

```just
# Remove the native Fleet package before the first Nix-managed Orbit activation.
migrate-cachyos-orbit:
    #!/usr/bin/env bash
    set -euo pipefail

    package=fleet-osquery
    if ! /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
        echo "Native Fleet package '$package' is already absent; no migration is needed."
        exit 0
    fi

    sudo /usr/bin/systemctl stop orbit.service 2>/dev/null || true
    sudo /usr/bin/pacman -R "$package"
    sudo /usr/bin/systemctl daemon-reload
```

Do not make this recipe a dependency of another recipe. Document it in the
Framework host README immediately before the first system-manager activation.

- [ ] **Step 5: Run exact eval and green Orbit contracts**

Run:

```bash
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk bash tests/justfile-contract.sh .
rtk nix build .#checks.x86_64-linux.configuration-contract .#checks.x86_64-linux.justfile-contract --no-link
```

Expected: all commands exit 0 without invoking `pacman` or systemd.

- [ ] **Step 6: Commit Orbit migration behavior**

```bash
rtk git add parts/checks.nix tests/justfile-contract.sh modules/system-manager/orbit.nix justfile hosts/cachyos-framework13-system-manager/README.md
rtk git diff --cached --check
rtk git commit -m "refactor: make Orbit migration explicit"
```

---

### Task 3: Restore Nix defaults and harden root commands

**Files:**

- Modify: `parts/checks.nix`
- Modify: `tests/justfile-contract.sh`
- Modify: `modules/profiles/base.nix`
- Modify: `hosts/reddit-mac/configuration.nix`
- Modify: `hosts/cachyos-framework13-system-manager/configuration.nix`
- Modify: `justfile`

**Interfaces:**

- Consumes: evaluated Nix settings and rendered Just maintenance commands.
- Produces: default download buffering, effective `trusted-users = [ "root" ]`, and absolute root Nix executables.

- [ ] **Step 1: Add failing evaluated policy assertions**

Define:

```nix
  darwinSystem = config.flake.darwinConfigurations.PNH46YXX3Y.config;
```

Add:

```nix
          {
            assertion = (razerSystem.nix.settings.download-buffer-size or 1048576) == 1048576;
            message = "Linux must use the upstream 1 MiB Nix download buffer default";
          }
          {
            assertion = (darwinSystem.nix.settings.download-buffer-size or 1048576) == 1048576;
            message = "Darwin must use the upstream 1 MiB Nix download buffer default";
          }
          {
            assertion = frameworkSystem.nix.settings.trusted-users == [ "root" ];
            message = "Framework Nix trusted-users must use the root-only default";
          }
```

Extend `tests/justfile-contract.sh` with rendered-command expectations:

```bash
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix --extra-experimental-features" \
  system-manager-switch cachyos-framework13
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage -d" \
  gc
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than 7d" \
  gc-older 7
expect_rendered \
  "sudo /nix/var/nix/profiles/default/bin/nix-store --optimise" \
  optimize

for recipe_output in \
  "$(just --dry-run system-manager-switch cachyos-framework13)" \
  "$(just --dry-run bootstrap-cachyos)" \
  "$(just --dry-run gc)" \
  "$(just --dry-run gc-older 7)" \
  "$(just --dry-run optimize)"
do
  case "$recipe_output" in
    *'sudo env "PATH=$PATH"'*)
      echo "Root Nix commands must not forward the caller PATH" >&2
      exit 1
      ;;
  esac
done
```

- [ ] **Step 2: Prove the settings and root-command tests fail**

Run:

```bash
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk bash tests/justfile-contract.sh .
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
```

Expected: all three target evals succeed; the Just test reports the missing
absolute root binary; the contract reports both oversized buffers and expanded
trusted users.

- [ ] **Step 3: Remove local Nix setting overrides**

Delete:

```nix
download-buffer-size = 671088640;
download-buffer-size = 1671088640;
trusted-users = [ "root" "@wheel" "adriel" ];
```

Do not replace them with new explicit values.

- [ ] **Step 4: Use root-profile executables**

Replace root invocations only:

```text
sudo /nix/var/nix/profiles/default/bin/nix
sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage
sudo /nix/var/nix/profiles/default/bin/nix-store
```

Use the absolute Nix binary in both `system-manager-switch` and
`bootstrap-cachyos`. Keep user-level `nix` and `nix-collect-garbage`
invocations unchanged.

- [ ] **Step 5: Run exact evals and green policy contracts**

Run:

```bash
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk bash tests/justfile-contract.sh .
rtk nix build .#checks.x86_64-linux.configuration-contract .#checks.x86_64-linux.justfile-contract --no-link
```

Expected: all commands exit 0.

- [ ] **Step 6: Commit default restoration and root hardening**

```bash
rtk git add parts/checks.nix tests/justfile-contract.sh modules/profiles/base.nix hosts/reddit-mac/configuration.nix hosts/cachyos-framework13-system-manager/configuration.nix justfile
rtk git diff --cached --check
rtk git commit -m "refactor: restore Nix defaults and root paths"
```

---

### Task 4: Scope CUDA `llama-cpp` to Razer

**Files:**

- Modify: `parts/checks.nix`
- Modify: `parts/home-manager.nix`
- Modify: `users/adriel/common.nix`
- Modify: `users/adriel/default.nix`

**Interfaces:**

- Consumes: evaluated Home Manager package lists and Nixpkgs `cudaCapabilities`.
- Produces: one CUDA `llama-cpp` in both Razer evaluations, no Dell `llama-cpp`, and architecture 120 only.

- [ ] **Step 1: Add failing host-scope and architecture assertions**

Add these helpers to `parts/checks.nix`:

```nix
  dellSystem = config.flake.nixosConfigurations.dell-plex.config;
  packagesNamed =
    pname: packages:
    builtins.filter (package: (package.pname or null) == pname) packages;
  razerStandaloneLlama = packagesNamed "llama-cpp" razerHome.home.packages;
  razerEmbeddedLlama =
    packagesNamed "llama-cpp" razerSystem.home-manager.users.adriel.home.packages;
  dellLlama =
    packagesNamed "llama-cpp" dellSystem.home-manager.users.adriel.home.packages;
  cudaArchitectureFlags =
    package:
    builtins.filter
      (flag: lib.hasPrefix "-DCMAKE_CUDA_ARCHITECTURES" flag)
      (package.cmakeFlags or [ ]);
  targetsOnlySm120 =
    package:
    cudaArchitectureFlags package == [ "-DCMAKE_CUDA_ARCHITECTURES:STRING=120" ];
```

Add:

```nix
          {
            assertion = razerHomeOutput.pkgs.config.cudaCapabilities == [ "12.0" ];
            message = "standalone Razer Home Manager must target CUDA compute capability 12.0";
          }
          {
            assertion =
              builtins.length razerStandaloneLlama == 1
              && targetsOnlySm120 (builtins.head razerStandaloneLlama);
            message = "standalone Razer Home Manager must provide CUDA llama-cpp for sm_120 only";
          }
          {
            assertion =
              builtins.length razerEmbeddedLlama == 1
              && targetsOnlySm120 (builtins.head razerEmbeddedLlama);
            message = "embedded Razer Home Manager must provide CUDA llama-cpp for sm_120 only";
          }
          {
            assertion = dellLlama == [ ];
            message = "Dell Home Manager must not inherit Razer CUDA llama-cpp";
          }
```

- [ ] **Step 2: Prove the CUDA contract fails before the move**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
```

Expected: all exact target evals succeed; the contract reports that standalone
Razer targets the full default capability list and Dell still inherits
`llama-cpp`.

- [ ] **Step 3: Add per-output Nixpkgs configuration**

Extend `mkHomeConfig` in `parts/home-manager.nix`:

```nix
  mkHomeConfig =
    {
      system ? systems.linux,
      userConfig,
      extraModules ? [ ],
      extraOverlays ? [ ],
      extraNixpkgsConfig ? { },
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [ inputs.niri.overlays.niri ] ++ extraOverlays;
        config = {
          allowUnfree = true;
        }
        // extraNixpkgsConfig;
      };
      extraSpecialArgs = commonSpecialArgs;
      modules = [
        inputs.sops-nix.homeManagerModules.sops
        inputs.niri.homeModules.niri
      ]
      ++ extraModules
      ++ [ userConfig ];
    };
```

Set only the standalone Razer output:

```nix
    razer14 = mkHomeConfig {
      userConfig = ../users/adriel;
      extraNixpkgsConfig.cudaCapabilities = [ "12.0" ];
    };
```

- [ ] **Step 4: Move the package to the Razer wrapper**

Remove `(llama-cpp.override { cudaSupport = true; })` from
`users/adriel/common.nix`.

Change the Razer wrapper argument set and add:

```nix
{ pkgs, ... }:

{
  home.packages = [
    (pkgs.llama-cpp.override { cudaSupport = true; })
  ];
}
```

Do not add it to the Dell or Framework user wrappers.

- [ ] **Step 5: Run exact evals and inspect the real derivation flags**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
rtk nix eval --json .#homeConfigurations.razer14.config.home.packages --apply 'packages: map (package: package.cmakeFlags or []) (builtins.filter (package: (package.pname or null) == "llama-cpp") packages)'
```

Expected: every command exits 0, and the final JSON contains exactly one
`llama-cpp` flag list with
`-DCMAKE_CUDA_ARCHITECTURES:STRING=120`, not the former semicolon-separated
multiarchitecture target.

- [ ] **Step 6: Commit the host-scoped CUDA package**

```bash
rtk git add parts/checks.nix parts/home-manager.nix users/adriel/common.nix users/adriel/default.nix
rtk git diff --cached --check
rtk git commit -m "refactor: scope CUDA llama-cpp to Razer"
```

---

### Task 5: Lock resource policy and refresh exception documentation

**Files:**

- Modify: `parts/checks.nix`
- Modify: `TODO.md`

**Interfaces:**

- Consumes: evaluated Framework systemd drop-ins and the completed read-only TODO audit.
- Produces: regression protection for unchanged endpoint limits and current canonical TODO targets.

- [ ] **Step 1: Add evaluated endpoint-policy invariants**

Define:

```nix
  orbitDropIn =
    frameworkSystem.environment.etc."systemd/system/orbit.service.d/50-resource-limits.conf".text;
  duoDropIn =
    frameworkSystem.environment.etc."systemd/system/duo-desktop.service.d/50-resource-limits.conf".text;
```

Add:

```nix
          {
            assertion =
              lib.hasInfix "CPUWeight=100" orbitDropIn
              && lib.hasInfix "CPUQuota=20%" orbitDropIn
              && lib.hasInfix "MemoryHigh=480M" orbitDropIn
              && lib.hasInfix "MemoryMax=500M" orbitDropIn;
            message = "Orbit resource controls must remain at the measured policy";
          }
          {
            assertion =
              lib.hasInfix "CPUWeight=1" duoDropIn
              && lib.hasInfix "CPUQuota=0.25%" duoDropIn
              && lib.hasInfix "MemoryHigh=80M" duoDropIn
              && lib.hasInfix "MemoryMax=96M" duoDropIn;
            message = "Duo resource controls must remain at the measured policy";
          }
```

The existing Falcon assertion remains unchanged. This is a characterization
contract for deliberately unchanged production behavior.

- [ ] **Step 2: Verify the characterization contract**

Run:

```bash
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
```

Expected: both commands exit 0. Mentally mutating Orbit to `CPUQuota=21%` or
Duo to `CPUQuota=1%` must make the corresponding literal assertion false.

- [ ] **Step 3: Update all current output references in `TODO.md`**

Replace current validation and affected-output references:

```text
nixosConfigurations.dell        -> nixosConfigurations.dell-plex
homeConfigurations.adriel       -> homeConfigurations.razer14
systemConfigs.cachyos-framework -> systemConfigs.cachyos-framework13
```

Record the 2026-07-28 audit without resolving an exception:

- Fleet PR #525702 remains open at `d2c59b6d82b9a81e12892b1d3fc6356fa383d7d1`; Fleet remains absent from upstream `master` and `nixos-unstable`.
- Keychron's upstream hidraw rule still has no `GROUP=` fallback.
- system-manager still has no Bolt module and Framework firmware issue #185 remains open.
- Apple Studio Display USB4/HBR3 reports remain unresolved.
- Private aiKitten `main` remains `12b10b525afc9d7f9895f610a6a82714a87b1680`; only the SSH ref was freshly verifiable.
- Framework BIOS 4.02 is a future controlled retest opportunity, not evidence that either display workaround is obsolete.

- [ ] **Step 4: Confirm only intentional historical names remain**

Run:

```bash
rtk git grep -n -E 'nixosConfigurations\\.dell([^a-z-]|$)|homeConfigurations\\.adriel|systemConfigs\\.cachyos-framework([^1]|$)|\\.#[{]?(dell|adriel)([^a-z-]|$)' -- ':!docs/superpowers/specs/2026-07-28-configuration-hardening-design.md' ':!docs/superpowers/plans/2026-07-28-configuration-hardening.md'
```

Expected: no matches in active configuration, operational docs, or TODO
validation instructions.

- [ ] **Step 5: Commit policy protection and TODO refresh**

```bash
rtk git add parts/checks.nix TODO.md
rtk git diff --cached --check
rtk git commit -m "docs: refresh configuration exception audit"
```

---

### Task 6: Full nonactivating verification

**Files:**

- Verify all files changed by Tasks 1-5.

**Interfaces:**

- Consumes: the completed strict cutover.
- Produces: fresh evidence that every target evaluates, lightweight checks build, Just behavior is correct, and the user's lockfile remains outside all commits.

- [ ] **Step 1: Format changed Nix files**

Run the formatter only on changed Nix files:

```bash
rtk nixfmt parts/checks.nix parts/nixos.nix parts/home-manager.nix parts/system-manager.nix modules/system-manager/bolt.nix modules/system-manager/niri.nix modules/system-manager/orbit.nix modules/profiles/base.nix hosts/reddit-mac/configuration.nix hosts/cachyos-framework13-system-manager/configuration.nix users/adriel/common.nix users/adriel/default.nix
```

If formatting changes tracked content, repeat the exact affected-output eval and
amend only the commit that owns those files.

- [ ] **Step 2: Evaluate every exact target**

Run:

```bash
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
```

Expected: six derivation paths and exit code 0.

- [ ] **Step 3: Build the lightweight and Framework checks**

Run:

```bash
rtk nix build .#checks.x86_64-linux.system-cachyos-framework13 .#checks.x86_64-linux.configuration-contract .#checks.x86_64-linux.justfile-contract .#checks.x86_64-linux.nix-format .#checks.x86_64-linux.shell-syntax --no-link
```

Expected: exit code 0. This builds the Framework system-manager derivation but
does not activate it.

- [ ] **Step 4: Evaluate the complete local flake check set**

Run:

```bash
rtk just check
```

Expected: `all checks passed`; the pre-existing `mesa.drivers` deprecation
warning is allowed.

- [ ] **Step 5: Verify rendered command behavior**

Run:

```bash
rtk just --list
rtk bash tests/justfile-contract.sh .
rtk just --dry-run switch razer14
rtk just --dry-run build dell-plex
rtk just --dry-run home-build razer14
rtk just --dry-run darwin-build PNH46YXX3Y
rtk just --dry-run system-manager-switch cachyos-framework13
rtk just --dry-run migrate-cachyos-orbit
rtk just --dry-run bootstrap-cachyos
```

Expected: required arguments are visible in `just --list`, canonical targets
appear in every rendered command, the migration is interactive, and nothing is
executed.

- [ ] **Step 6: Audit the final diff and user-owned lockfile**

Run:

```bash
rtk git diff --check
rtk git status --short
rtk git diff --name-only 338beec..HEAD
rtk git diff --cached --name-only
```

Expected: no staged files; `flake.lock` remains the sole unrelated uncommitted
user change; the range from the approved-spec commit through the implementation
contains no `flake.lock`.

- [ ] **Step 7: Review the approved specification line by line**

Compare the result with
`docs/superpowers/specs/2026-07-28-configuration-hardening-design.md` and verify:

- strict output cutover with no aliases
- explicit targets for every generic recipe
- explicit, interactive Orbit migration
- default download buffers and root-only trust
- absolute root Nix executables
- Razer-only `sm_120` CUDA `llama-cpp`
- unchanged endpoint-agent resource limits
- all six exact evals and no activation
