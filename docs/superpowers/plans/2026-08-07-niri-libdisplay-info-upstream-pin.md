# Niri libdisplay-info Upstream Pin Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Repair the Niri evaluation regression in the existing broad lock update by temporarily pinning Niri-flake to its upstream `libdisplay-info_0_3` PR commit.

**Architecture:** Keep Niri-flake's modules and `pkgs.niri-unstable` overlay unchanged. Pin only the `niri` flake input to upstream PR #1850 through the official repository, record the exception in `TODO.md`, and validate the combined dirty lock state without staging the user's other lock updates.

**Tech Stack:** Nix flakes, NixOS, Home Manager, flake-parts configuration contracts

## Global Constraints

- Target config: `homeConfigurations.razer14`.
- Validation host: `razer14` / NixOS.
- Preserve every existing broad `flake.lock` update except the intentional `niri` node change.
- Run the exact Razer Home Manager eval after every Nix edit.
- Do not replace `pkgs.niri-unstable` with `pkgs.niri`.
- Do not stage or commit the user's existing broad `flake.lock` changes.
- Do not activate any Home Manager or NixOS generation.
- Do not modify unrelated untracked files.

---

### Task 1: Pin Niri-flake to the upstream dependency fix

**Files:**
- Modify: `flake.nix`
- Modify: `flake.lock`
- Modify: `TODO.md`

**Interfaces:**
- Consumes: root input `nixpkgs` at `b7c2ada94fe99c15b0dbcf4d11fd7850b957a436`, Niri-flake PR #1850 commit `6bb99ff875919f03ea6054026619d999061e1170`, and existing `programs.niri.package = pkgs.niri-unstable` declarations.
- Produces: a Niri-flake overlay compatible with `libdisplay-info_0_3` and a documented rollback path to unpinned upstream `main`.

- [ ] **Step 1: Reproduce the failing regression test**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: FAIL while evaluating `pkgs.niri-unstable` because
`libdisplay-info_0_2` has been removed from the locked Nixpkgs revision.

- [ ] **Step 2: Pin the declared Niri-flake input**

Change only the existing `niri.url` in `flake.nix`:

```nix
niri = {
  url = "github:sodiboo/niri-flake/6bb99ff875919f03ea6054026619d999061e1170";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

- [ ] **Step 3: Run the mandatory target eval without writing the lock**

Run:

```bash
rtk nix eval --no-write-lock-file .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: evaluation returns the Home Manager generation derivation path and
reports that the `niri` lock entry would move from `9ee3e13...` to
`6bb99ff...`.

- [ ] **Step 4: Update only the Niri lock node**

Run:

```bash
rtk nix flake update niri
```

Expected: only input `niri` changes to
`github:sodiboo/niri-flake/6bb99ff875919f03ea6054026619d999061e1170`;
all other already-dirty input revisions remain unchanged.

- [ ] **Step 5: Run the mandatory target eval after the lock edit**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: evaluation returns the Home Manager generation derivation path.

- [ ] **Step 6: Record the temporary upstream exception**

Add this active entry under `Pinned exceptions to revisit:` in `TODO.md`:

```markdown
- The `niri` flake input is temporarily pinned to Niri-flake PR #1850 commit `6bb99ff875919f03ea6054026619d999061e1170`: targets `homeConfigurations.razer14`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, `nixosConfigurations.dell-plex`, and `checks.x86_64-linux.configuration-contract`. Original issue: Nixpkgs PR #549132 removed `libdisplay-info_0_2`, but locked Niri-flake `9ee3e13b60643448228353097880521658b2fe0e` still requested and asserted version 0.2 even though its locked Niri source `feb3e43f1475e0865bb89cbd1e898b34d1d2ccf6` already contains the Niri PR #4366 migration to `libdisplay-info_0_3`. Upstream fix: https://github.com/sodiboo/niri-flake/pull/1850 at commit `6bb99ff875919f03ea6054026619d999061e1170`. Obsolescence check: after PR #1850 or an equivalent fix merges, restore `niri.url = "github:sodiboo/niri-flake"`, update only the `niri` input, and remove this entry when the configuration contract plus all four exact Home Manager/NixOS evaluations pass.
```

- [ ] **Step 7: Verify formatting and every affected output**

Run:

```bash
rtk nix fmt -- --ci .
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
```

Expected: the formatter reports zero changed files and every evaluation returns
a derivation path without the removed-package failure.

- [ ] **Step 8: Review scope without staging the dirty lock**

Run:

```bash
rtk git diff --check
rtk git diff -- flake.nix flake.lock TODO.md
rtk git status --short
```

Expected: the intentional repair is limited to the Niri URL, Niri lock node,
and one active TODO entry. Existing unrelated lock updates and untracked files
remain present and unstaged.
