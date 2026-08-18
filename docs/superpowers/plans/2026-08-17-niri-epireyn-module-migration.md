# Niri epireyn Module Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Follow `epireyn/niri-flake` main for structured configuration modules while selecting Niri and Xwayland Satellite exclusively from the primary Nixpkgs input and disabling the fork cache.

**Architecture:** First repair the existing system-manager contract by making system-manager follow primary Nixpkgs and injecting only `fleet-orbit` and `fleet-desktop` from the target-scoped Fleet fork. Then preserve the existing `inputs.niri` interface and module imports so all structured `programs.niri.settings` and action helpers remain compatible. Remove the fork package overlay, select `pkgs.niri` and `pkgs.xwayland-satellite`, disable `niri-flake.cache`, update only the `system-manager` and `niri` lock graphs, and record the active exceptions and resolved history.

**Tech Stack:** Nix flakes, NixOS modules, Home Manager modules, flake-parts checks

## Global Constraints

- Follow `github:epireyn/niri-flake` main; do not hard-pin the URL.
- Do not enable or trust the fork's binary cache.
- Use `programs.niri.package = pkgs.niri` in system and Home Manager scopes.
- Use `pkgs.xwayland-satellite`, not the fork overlay package.
- Preserve all unrelated tracked and untracked work.
- Produce exactly one commit for the complete migration and documentation.
- Do not activate a NixOS, Home Manager, Darwin, or system-manager generation.
- Exact eval is the minimum validation; CUDA-heavy builds are out of scope.

---

### Task 0: Restore the system-manager input contract

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `parts/system-manager.nix`
- Modify: `parts/checks.nix`
- Modify: `TODO.md`

- [ ] **Step 1: Preserve the existing red contract evidence**

The exact `systemConfigs.cachyos-framework13` and
`checks.x86_64-linux.configuration-contract` evals currently fail because
system-manager defines `nix.enable` and `nix.nrBuildUsers`, while the pinned
Fleet fork's NixOS `config/nix.nix` module does not declare those options.

- [ ] **Step 2: Narrow the Fleet exception instead of patching either upstream**

Make `inputs.system-manager.inputs.nixpkgs` follow primary `nixpkgs`. Pass a
target-scoped overlay to `makeSystemConfig` that exposes exactly
`fleet-orbit` and `fleet-desktop` from `inputs.nixpkgs-fleet`. Update the
contract to require system-manager to follow primary Nixpkgs and both Framework
Orbit packages to retain exact identity with the Fleet fork.

- [ ] **Step 3: Persist and validate the targeted contract repair**

Run:

```bash
rtk nix flake update system-manager
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: only the system-manager input relationship changes in the lock graph,
and both existing red evals return derivation paths.

---

### Task 1: Migrate the Niri module source and package trust boundary

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `parts/home-manager.nix`
- Modify: `parts/lib.nix`
- Modify: `parts/checks.nix`
- Modify: `modules/shared/nix-cache-settings.nix`
- Modify: `modules/system/niri.nix`
- Modify: `modules/home-manager/niri/default.nix`
- Modify: `TODO.md`
- Create: `docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md`
- Create: `docs/superpowers/plans/2026-08-17-niri-epireyn-module-migration.md`

**Interfaces:**
- Consumes: `inputs.niri.nixosModules.niri`, `inputs.niri.homeModules.niri`, `programs.niri.settings`, and `config.lib.niri.actions`.
- Produces: identical module/configuration interfaces backed by `epireyn/niri-flake` main, with Niri 26.04 and Xwayland Satellite 0.8.2 selected from primary Nixpkgs and no fork cache settings.

- [ ] **Step 1: Capture the failing trust-boundary assertions**

Run:

```bash
rtk nix eval --raw .#homeConfigurations.razer14.config.programs.niri.package.version
rtk nix eval --json .#nixosConfigurations.razer14.config.niri-flake.cache.enable
rtk proxy rg -n 'inputs\.niri\.overlays\.niri|pkgs\.niri-unstable|pkgs\.xwayland-satellite-unstable' parts modules
```

Expected before implementation: the package version is an `unstable-*`
snapshot, cache enable evaluates to `true`, and the search finds both overlay
imports plus the unstable package references.

- [ ] **Step 2: Change the declared input and package selections**

Apply these exact source changes:

```nix
# flake.nix
niri = {
  url = "github:epireyn/niri-flake";
  inputs.nixpkgs.follows = "nixpkgs";
};

# modules/system/niri.nix, outside the enabled config
niri-flake.cache.enable = false;

# modules/system/niri.nix, inside the enabled config
programs.niri.package = pkgs.niri;

# modules/home-manager/niri/default.nix
programs.niri.package = pkgs.niri;
programs.niri.settings.xwayland-satellite.path = lib.getExe pkgs.xwayland-satellite;
```

Remove `inputs.niri.overlays.niri` from `parts/home-manager.nix` and
`parts/lib.nix`, preserving every unrelated overlay and Nixpkgs option. Remove
the old Niri Cachix URL and key from the shared cache policy. Add configuration
contract assertions for exact Nixpkgs Niri package identity, exact Xwayland
Satellite path, disabled fork cache on both NixOS outputs, and absence of both
the old and fork cache URLs/keys.

- [ ] **Step 3: Evaluate the changed declarations without persisting a lock update**

Run:

```bash
rtk nix eval --no-write-lock-file .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: Nix reports the temporary input move to `epireyn/niri-flake` and
returns a Home Manager derivation path using `pkgs.niri`.

- [ ] **Step 4: Update only the Niri lock graph**

Run:

```bash
rtk nix flake update niri
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: the root `niri` node moves to `epireyn/niri-flake` main and only its
nested Niri, stable-Nixpkgs, and Xwayland Satellite nodes change. No unrelated
root input advances. The immediate exact evaluation returns a Home Manager
derivation path using the persisted lock graph.

- [ ] **Step 5: Record the active exception and resolved pin**

Replace the first active TODO entry with text covering:

```markdown
- The `niri` input follows the community-maintained `github:epireyn/niri-flake` fork while this repository still depends on its structured Home Manager settings renderer and `config.lib.niri.actions`: targets `homeConfigurations.razer14`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, `nixosConfigurations.dell-plex`, and `checks.x86_64-linux.configuration-contract`. Original upstream `sodiboo/niri-flake` stalled at `9ee3e13b60643448228353097880521658b2fe0e`; PR #1850 closed unmerged and issue #1851 remains open after Nixpkgs removed `libdisplay-info_0_2`. The fork is used only for evaluated modules: `inputs.niri.overlays.niri` is not imported, both scopes select primary `pkgs.niri`, Xwayland Satellite comes from primary Nixpkgs, and `niri-flake.cache.enable = false`. Upstream/fork references: https://github.com/sodiboo/niri-flake/issues/1813 and https://github.com/epireyn/niri-flake. Obsolescence check: prefer removing this input once upstream Home Manager and Nixpkgs cover the structured settings and action-helper behavior; then remove the fork modules and confirm the five exact evaluations pass.
```

Add a dated resolved-history entry explaining that the immutable PR #1850
commit pin was removed because the PR closed unmerged, the active fork carries
the dependency fix, package/cache trust moved to primary Nixpkgs, and all five
exact evaluations were used for validation.

- [ ] **Step 6: Verify package identity, cache refusal, and removed overlay references**

Run:

```bash
rtk nix eval --raw .#homeConfigurations.razer14.config.programs.niri.package.version
rtk nix eval --json .#homeConfigurations.razer14 --apply 'c: c.config.programs.niri.package.outPath == c.pkgs.niri.outPath'
rtk nix eval --json .#homeConfigurations.razer14 --apply 'c: c.config.programs.niri.settings.xwayland-satellite.path == c.pkgs.lib.getExe c.pkgs.xwayland-satellite'
rtk nix eval --json .#nixosConfigurations.razer14.config.niri-flake.cache.enable
rtk nix eval --json .#nixosConfigurations.dell-plex.config.niri-flake.cache.enable
rtk proxy rg -n 'inputs\.niri\.overlays\.niri|pkgs\.niri-unstable|pkgs\.xwayland-satellite-unstable|niri-epireyn\.cachix\.org' flake.nix parts modules
```

Expected: version `26.04`, both identity comparisons `true`, both cache values
`false`, and the search exits 1 with no matches.

- [ ] **Step 7: Evaluate every affected output**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
rtk nix build .#homeConfigurations.razer14.config.xdg.configFile.niri-config.source --no-link
rtk nix build .#homeConfigurations.cachyos-framework13.config.xdg.configFile.niri-config.source --no-link
```

Expected: every command returns a derivation path.

- [ ] **Step 8: Verify formatting and exact scope**

Run:

```bash
rtk nix fmt -- --ci .
rtk git diff --check
rtk git diff -- flake.nix flake.lock parts/home-manager.nix parts/lib.nix parts/system-manager.nix parts/checks.nix modules/shared/nix-cache-settings.nix modules/system/niri.nix modules/home-manager/niri/default.nix TODO.md
rtk proxy git status --short --untracked-files=all
```

Expected: formatting and whitespace checks pass; the tracked diff contains
only this migration; unrelated untracked files remain untouched.

- [ ] **Step 9: Stage only the migration and create its single rollback commit**

Run:

```bash
rtk git add flake.nix flake.lock parts/home-manager.nix parts/lib.nix parts/system-manager.nix parts/checks.nix modules/shared/nix-cache-settings.nix modules/system/niri.nix modules/home-manager/niri/default.nix TODO.md
rtk git add -f docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md docs/superpowers/plans/2026-08-17-niri-epireyn-module-migration.md
rtk git diff --cached --check
rtk git diff --cached --stat
rtk git commit -m "fix: migrate Niri modules and restore contract"
```

Expected: exactly one commit is created and unrelated untracked files remain
unstaged. Do not amend or create a second migration commit.

- [ ] **Step 10: Verify the committed state without activating it**

Run:

```bash
rtk git show --stat --oneline --summary HEAD
rtk proxy git status --short --untracked-files=all
```

Expected: HEAD is the single migration commit and status lists only the
pre-existing unrelated untracked files.
