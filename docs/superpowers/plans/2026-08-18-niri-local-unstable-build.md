# Niri Local Unstable Build Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Select epireyn's pinned `niri-unstable` derivation for every Linux Niri consumer, compile it without binary substitution, retain the primary Nixpkgs package only for disabled Darwin evaluation, and reject both Niri Cachix generations.

**Architecture:** The existing epireyn input remains pinned and follows primary Nixpkgs. A configuration-contract assertion is changed first so it fails while Linux consumers still use stable `pkgs.niri`; the NixOS and Home Manager modules then select the direct fork package without importing its overlay. Cache rejection remains unconditional, Xwayland Satellite remains on primary Nixpkgs, and the final package is forcibly rebuilt with substitution disabled because the currently activated machine still trusts the retired cache.

**Tech Stack:** Nix flakes, NixOS modules, Home Manager modules, flake-parts checks

## Global Constraints

- Use `inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable` directly on Linux; do not import `inputs.niri.overlays.niri`.
- Keep `pkgs.niri` only as the disabled `aarch64-darwin` evaluation fallback because epireyn publishes packages only for `x86_64-linux` and `aarch64-linux`.
- Keep `niri-flake.cache.enable = false` outside all enable guards.
- Reject both `niri.cachix.org` and `niri-epireyn.cachix.org` URLs and signing keys.
- Keep Xwayland Satellite on primary `pkgs.xwayland-satellite`.
- Force the exact configured Niri derivation to rebuild with `--option substitute false`; the live machine still trusts the retired cache until a separately approved activation.
- Update no flake inputs or lock nodes for this follow-up.
- Do not run any activation, switch, boot, or `nix run` command.
- Preserve unrelated work and stage explicit paths only.

---

### Task 1: Enforce and implement the Linux package boundary

**Files:**
- Modify: `parts/checks.nix`
- Modify: `modules/system/niri.nix`
- Modify: `modules/home-manager/niri/default.nix`

**Interfaces:**
- Consumes: `inputs.niri.packages.${systems.linux}.niri-unstable`, primary `pkgs.niri`, and the existing `programs.niri.package` option.
- Produces: exact package identity for all x86_64-linux consumers and a Darwin-safe disabled fallback.

- [ ] **Step 1: Write the failing package-identity contract**

Add the direct package beside the existing output bindings in
`parts/checks.nix`:

```nix
  niriUnstable = inputs.niri.packages.${systems.linux}.niri-unstable;
```

Replace the current primary-Nixpkgs package assertion with:

```nix
          {
            assertion =
              toString razerHome.programs.niri.package == toString niriUnstable
              && toString frameworkHome.programs.niri.package == toString niriUnstable
              && toString razerSystem.programs.niri.package == toString niriUnstable
              && toString dellSystem.programs.niri.package == toString niriUnstable
              && toString razerEmbeddedHome.programs.niri.package == toString niriUnstable
              && toString dellEmbeddedHome.programs.niri.package == toString niriUnstable
              && lib.hasPrefix "unstable-" niriUnstable.version
              &&
                darwinEmbeddedHome.programs.niri.package.meta.position
                == darwinSystemOutput.pkgs.niri.meta.position;
            message = "Linux Niri packages must use the direct fork unstable derivation while disabled Darwin stays on primary nixpkgs";
          }
```

- [ ] **Step 2: Run the contract and verify the expected red result**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: evaluation fails only with the new Linux Niri package-identity
message because the modules still select `pkgs.niri`.

- [ ] **Step 3: Select the direct package in the NixOS module**

Extend the existing `let` in `modules/system/niri.nix` and use the binding
outside the enable guard:

```nix
let
  cfg = config.local.niri;
  niriPackage = inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable;
in
```

```nix
      niri-flake.cache.enable = false;
      programs.niri.package = niriPackage;
```

Immediately evaluate both affected NixOS outputs:

```bash
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
```

Expected: both return derivation paths; Dell remains disabled but resolves the
same package explicitly.

- [ ] **Step 4: Select the package on Linux with a Darwin-safe fallback**

Add `inputs` to the argument set in
`modules/home-manager/niri/default.nix`, then add:

```nix
  niriPackage =
    if pkgs.stdenv.hostPlatform.isLinux then
      inputs.niri.packages.${pkgs.stdenv.hostPlatform.system}.niri-unstable
    else
      pkgs.niri;
```

Use the binding in the unconditional import fragment:

```nix
    { programs.niri.package = niriPackage; }
```

Immediately evaluate every output importing the Home Manager module:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
```

Expected: all five return derivation paths. Darwin must not attempt to access
the absent `inputs.niri.packages.aarch64-darwin` output.

- [ ] **Step 5: Verify the contract turns green**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
rtk nix eval --raw .#homeConfigurations.razer14.config.programs.niri.package.version
rtk nix eval --raw .#homeConfigurations.razer14.config.programs.niri.package.src.rev
rtk nix eval --raw .#darwinConfigurations.PNH46YXX3Y --apply 'c: c.config.home-manager.users."adriel.velazquez".programs.niri.package.version'
```

Expected: the contract returns a derivation path; Linux reports
`unstable-2026-08-14-6062844` and source revision
`606284464d4a99bb35710fee68192bc71085ee7c`; disabled Darwin reports `26.04`.

- [ ] **Step 6: Apply independent-review contract hardening**

Extend the cache-negative assertion to Darwin and assert that the fork's
`nixpkgs` input resolves to the primary input's `outPath`. Re-evaluate the
configuration contract after both changes.

---

### Task 2: Record the source and binary trust exceptions

**Files:**
- Modify: `flake.nix`
- Modify: `TODO.md`
- Modify: `docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md`

**Interfaces:**
- Consumes: the exact locked epireyn and upstream Niri revisions plus the evaluated cache policy.
- Produces: an actionable exception record with independent module, package, and cache exit conditions.

- [ ] **Step 1: Replace the stale active Niri exception wording**

Replace the first `TODO.md` entry with these two independently removable
exceptions:

```markdown
- The `niri` input follows the community-maintained `github:epireyn/niri-flake` main branch because this repository still depends on its structured Home Manager settings renderer and `config.lib.niri.actions`: targets `homeConfigurations.razer14`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, `nixosConfigurations.dell-plex`, `darwinConfigurations.PNH46YXX3Y`, `systemConfigs.cachyos-framework13` through shared cache policy, and `checks.x86_64-linux.configuration-contract`. Original issue: `sodiboo/niri-flake` stalled at `9ee3e13b60643448228353097880521658b2fe0e`; after Nixpkgs PR #549132 removed `libdisplay-info_0_2`, its PR #1850 closed unmerged and issue #1851 remained open. The successor fork was announced in https://github.com/sodiboo/niri-flake/issues/1813 and is maintained at https://github.com/epireyn/niri-flake. The separate Linux package-source exception is recorded below. No fork overlay is imported, `niri-flake.cache.enable = false` is unconditional, both Niri cache generations are rejected, and Xwayland Satellite remains primary `pkgs.xwayland-satellite`. Obsolescence check (updated 2026-08-18): locked Home Manager includes commit `5a9c98a31a388f97ece5fda45de08cc16e4bed2a` and native `wayland.windowManager.niri` structured settings/validation from https://github.com/nix-community/home-manager/pull/8700. It lacks `config.lib.niri.actions`, but those helpers can be rewritten as direct KDL-shaped attributes. In a dedicated migration, convert settings and binds, compare both rendered KDL files, switch NixOS session integration to the Nixpkgs module, and remove this module dependency. The input may remain until the independent package exception is also obsolete.
- `inputs.niri.packages.${system}.niri-unstable` is a temporary Linux package-source exception preserving the historically selected upstream-main Niri behavior. Pinned Nixpkgs `e5bdc4a41d4c072fe1e3787eaa0320a384741d44`, current `nixos-unstable` `ec2d622de0773551768cf98f3fc50cbcc003b9c5`, and current master `0ae2bc1419c3f345984c2629e72e7a631820fa4d` package only Niri 26.04 from tag `v26.04` and expose no native unstable/main-snapshot package. Locked epireyn revision `c3f09d27f760e1b4ec473b05851d6b8b32d8eb4b` packages upstream Niri main commit `606284464d4a99bb35710fee68192bc71085ee7c` as `unstable-2026-08-14-6062844`. Its public package output builds against primary Nixpkgs because `niri.inputs.nixpkgs.follows = "nixpkgs"`; do not import the overlay. Trust only the pinned, reviewed source and package expression: keep `niri-flake.cache.enable = false`, reject both old and epireyn Niri cache URLs/keys, and verify with `--rebuild --option substitute false` while the currently activated machine still trusts the retired cache. Disabled Darwin retains primary `pkgs.niri` because the fork publishes Linux packages only. Obsolescence check: after targeted `nixpkgs` or `niri` updates, inspect `pkgs.niri.version` and `src.rev`; return to primary Nixpkgs as soon as it offers equivalent freshness. Review the fork package-definition diff and upstream Niri revision before every targeted `niri` lock update.
```

- [ ] **Step 2: Validate documentation scope**

Update the nearby `flake.nix` comment to describe the source-versus-binary
trust boundary, and use `pkgs.stdenv.hostPlatform.system` in the design's
illustrative direct-package path.

Run:

```bash
rtk rg -n 'module-only|select primary `pkgs\.niri`|niri-epireyn\.cachix\.org|substitute false|unstable-2026-08-14-6062844' TODO.md docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md
rtk git diff --check -- TODO.md docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md
```

Expected: active wording describes source/package trust rather than
module-only use, both cache generations and the forced local-build command are
documented, and the whitespace check exits successfully.

---

### Task 3: Prove every target and compile Niri without substitution

**Files:**
- Verify: `modules/system/niri.nix`
- Verify: `modules/home-manager/niri/default.nix`
- Verify: `parts/checks.nix`
- Verify: `TODO.md`

**Interfaces:**
- Consumes: all seven flake outputs and the exact configured Niri derivation.
- Produces: fresh evaluation, contract, rendered-config, and local compilation evidence without activation.

- [ ] **Step 1: Evaluate all exact targets**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
rtk nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
rtk nix eval .#systemConfigs.cachyos-framework13.drvPath
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: all seven commands return derivation paths.

- [ ] **Step 2: Build the contract and rendered Niri configurations**

Run:

```bash
rtk nix build .#checks.x86_64-linux.configuration-contract --no-link
rtk nix build .#homeConfigurations.razer14.config.xdg.configFile.niri-config.source --no-link
rtk nix build .#homeConfigurations.cachyos-framework13.config.xdg.configFile.niri-config.source --no-link
```

Expected: all three builds exit successfully without activation.

- [ ] **Step 3: Force a source build of the exact configured compositor**

First show the live-versus-target cache distinction:

```bash
rtk nix config show | rtk rg -n 'substituters|trusted-public-keys|niri.*cachix'
rtk nix eval --json .#nixosConfigurations.razer14.config.nix.settings.substituters
rtk nix eval --json .#nixosConfigurations.razer14.config.nix.settings.trusted-public-keys
```

Then rebuild the exact configured derivation locally:

```bash
rtk nix build .#nixosConfigurations.razer14.config.programs.niri.package --no-link --rebuild --option substitute false
```

Expected: Nix rebuilds the compositor rather than substituting it, compares
the result if it already existed, and exits successfully. No epireyn or retired
Niri substituter/key is supplied to the command.

- [ ] **Step 4: Record the verified resolution**

Only after Steps 1-3 pass, add this resolved-history entry to `TODO.md`:

```markdown
- 2026-08-18: restored locally built Niri unstable after the initial epireyn migration temporarily selected Nixpkgs Niri 26.04. Original issue: configuration history showed that enabled Niri consumers had used `niri-unstable` snapshots since 2026-03-12, and the active binary remained upstream-main commit `7f26c3ee804fb6ed458ef7fb0e3c794f14e0b3bc`; selecting stable 26.04 therefore reduced source freshness. Resolution: every Linux system, standalone Home Manager, and embedded Home Manager consumer now selects epireyn's direct `niri-unstable` derivation `unstable-2026-08-14-6062844` from upstream commit `606284464d4a99bb35710fee68192bc71085ee7c`, built against primary Nixpkgs without importing the overlay. Disabled `aarch64-darwin` retains primary `pkgs.niri` because the fork publishes Linux packages only. Both Niri cache generations remain rejected and the compositor verification used `--rebuild --option substitute false` because the currently activated machine still trusted retired `niri.cachix.org`. Affected outputs: `homeConfigurations.razer14`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, `nixosConfigurations.dell-plex`, `darwinConfigurations.PNH46YXX3Y`, `systemConfigs.cachyos-framework13`, and `checks.x86_64-linux.configuration-contract`. Validation: all seven exact evaluations returned derivation paths, the contract and both rendered configurations built without activation, the exact compositor derivation rebuilt locally with substitution disabled, formatting and whitespace checks passed, and no switch command ran.
```

- [ ] **Step 5: Check formatting and repository scope**

Run:

```bash
rtk nix fmt -- --ci .
rtk git diff --check
rtk git status --short --untracked-files=all
rtk git diff -- TODO.md modules/home-manager/niri/default.nix modules/system/niri.nix parts/checks.nix docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md docs/superpowers/plans/2026-08-18-niri-local-unstable-build.md
```

Expected: formatting and whitespace checks pass; only the approved migration
follow-up remains in scope.

---

### Task 4: Commit the verified follow-up

**Files:**
- Commit: `flake.nix`
- Commit: `TODO.md`
- Commit: `modules/home-manager/niri/default.nix`
- Commit: `modules/system/niri.nix`
- Commit: `parts/checks.nix`
- Commit: `docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md`
- Commit: `docs/superpowers/plans/2026-08-18-niri-local-unstable-build.md`

**Interfaces:**
- Consumes: the verified working tree from Tasks 1-3.
- Produces: one reviewable rollback commit without activation.

- [ ] **Step 1: Inspect origin, status, and exact diff**

Run:

```bash
rtk git remote get-url origin
rtk git status --short --untracked-files=all
rtk git diff --check
```

Expected: origin is `github.com`, all intended files are visible, and no
whitespace errors exist.

- [ ] **Step 2: Stage only the approved files**

Run:

```bash
rtk git add flake.nix TODO.md modules/home-manager/niri/default.nix modules/system/niri.nix parts/checks.nix
rtk git add -f docs/superpowers/specs/2026-08-17-niri-epireyn-module-migration-design.md docs/superpowers/plans/2026-08-18-niri-local-unstable-build.md
rtk git diff --cached --check
rtk git diff --cached --stat
```

Expected: only the six listed files are staged.

- [ ] **Step 3: Create and inspect the follow-up commit**

Run:

```bash
rtk git commit -m "fix: build Niri unstable locally"
rtk git show --stat --oneline --summary HEAD
rtk git status --short --untracked-files=all
```

Expected: one follow-up commit is created, the worktree contains no remaining
changes from this task, and no system generation was activated.
