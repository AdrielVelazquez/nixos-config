# Antigravity CLI Skill Discovery Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Superpowers and `agp-9-upgrade` discoverable by Antigravity CLI from the Razer Home Manager configuration.

**Architecture:** Keep the reusable `ai-cli-skills` module as the single owner of AI CLI skill destinations. Correct only the Antigravity CLI root and the moved Android source path, with configuration-contract assertions covering the externally visible Home Manager file declarations.

**Tech Stack:** Nix, Home Manager, flake-parts configuration contracts

## Global Constraints

- Target config: `homeConfigurations.razer14`.
- Validation host: `razer14` / NixOS.
- Run the exact Home Manager eval after every Nix edit.
- Do not activate the generation with `home-manager switch`.
- Do not modify or stage unrelated untracked files.
- Add no package pin, fork, patch, secret, or `TODO.md` exception.

---

### Task 1: Repair Antigravity CLI skill discovery

**Files:**
- Modify: `parts/checks.nix`
- Modify: `modules/home-manager/ai-cli-skills.nix`

**Interfaces:**
- Consumes: `homeConfigurations.razer14.config.home.file`, `inputs.superpowers`, and `inputs.android-skills`.
- Produces: recursive Home Manager skill entries below `.gemini/antigravity-cli/skills` and a valid `agp-9-upgrade` source.

- [ ] **Step 1: Add the failing configuration-contract checks**

Add `razerHomeFiles = razerHome.home.file;` to the contract inputs and assertions equivalent to:

```nix
{
  assertion =
    builtins.hasAttr ".gemini/antigravity-cli/skills/using-superpowers" razerHomeFiles
    && razerHomeFiles.".gemini/antigravity-cli/skills/using-superpowers".recursive
    && !(builtins.hasAttr ".gemini/antigravity/skills/using-superpowers" razerHomeFiles);
  message = "Antigravity CLI must install recursive Superpowers skills in its supported global root";
}
{
  assertion =
    builtins.hasAttr ".gemini/antigravity-cli/skills/agp-9-upgrade" razerHomeFiles
    && builtins.pathExists razerHomeFiles.".gemini/antigravity-cli/skills/agp-9-upgrade".source;
  message = "Antigravity CLI must install agp-9-upgrade from an existing Android skills path";
}
```

- [ ] **Step 2: Run the mandatory target eval after the test edit**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: evaluation returns a derivation path because the contract is a separate check output.

- [ ] **Step 3: Verify the new contract fails for the current bug**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: FAIL with both Antigravity CLI skill contract messages because the supported root is absent.

- [ ] **Step 4: Implement the minimal module repair**

In `modules/home-manager/ai-cli-skills.nix`:

```nix
agp-9-upgrade = "build-system/agp/agp-9-upgrade";
```

Replace Antigravity's root with `.gemini/antigravity-cli/skills` in both `recursiveSkillRoots` and `home.file`, and generate both Antigravity skill sets recursively:

```nix
(mkSkillFiles ".gemini/antigravity-cli/skills" true superpowersSkills)
// (mkSkillFiles ".gemini/antigravity-cli/skills" true androidSkillDirs)
```

- [ ] **Step 5: Run the mandatory target eval after the implementation edit**

Run:

```bash
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
```

Expected: evaluation returns a derivation path.

- [ ] **Step 6: Verify the contract turns green**

Run:

```bash
rtk nix eval .#checks.x86_64-linux.configuration-contract.drvPath
```

Expected: evaluation returns the configuration-contract derivation path.

- [ ] **Step 7: Format and verify all affected outputs**

Run:

```bash
rtk nix fmt -- --check .
rtk nix eval .#homeConfigurations.razer14.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
```

Expected: formatter check and every exact output evaluation succeed.

- [ ] **Step 8: Commit the focused implementation**

```bash
rtk git add parts/checks.nix modules/home-manager/ai-cli-skills.nix
rtk git commit -m "fix: expose skills to Antigravity CLI"
```

Expected: only the two Nix files are included in the implementation commit.
