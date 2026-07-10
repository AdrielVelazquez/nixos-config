# Headroom Removal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove Headroom from all exported Linux configurations while preserving direct OpenCode LLM Platform access and independent RTK filtering.

**Architecture:** Delete the Headroom package and Home Manager service at their shared source, then remove every consumer of `local.headroom`. Reduce the Framework-only OpenCode work module to direct plugin settings so model discovery and inference return to the plugin's normal data path.

**Tech Stack:** Nix flakes, Home Manager, NixOS, OpenCode JSON generation, RTK.

## Global Constraints

- Target configs: `homeConfigurations.adriel`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, and `nixosConfigurations.dell`.
- Validation host: `framework13` running CachyOS.
- Preserve `modules/home-manager/rtk.nix` and the RTK command guidance in `AGENTS.md`.
- Do not delete `~/.headroom` or otherwise modify user runtime data.
- Do not run `home-manager switch`, `nixos-rebuild switch`, or any other activation command.
- Do not stage or commit files; another agent is working in this repository and the user did not request a commit.
- Do not modify unrelated files under the currently untracked `docs/superpowers/` tree.

---

## File Map

- Delete `modules/home-manager/headroom.nix`: removes the option set, package installation, and `headroom-proxy.service` declaration.
- Delete `packages/headroom-ai.nix`: removes the pinned upstream wheel derivation.
- Modify `modules/home-manager/default.nix`: stops importing the deleted module.
- Modify `modules/home-manager/opencode-work.nix`: keeps only LLM Platform plugin options and direct OpenCode settings.
- Modify `users/adriel/linux-baseline.nix`: removes the shared Headroom enable and environment variables.
- Modify `users/adriel-cachyos/default.nix`: removes Framework-specific OpenCode-to-Headroom routing.
- Modify `AGENTS.md`: removes Headroom integration policy while retaining RTK guidance under generic markers.
- Modify `TODO.md`: resolves the pinned Headroom exception with the measured removal reason and validation record.

### Task 1: Remove Headroom Runtime And Routing

**Files:**
- Delete: `modules/home-manager/headroom.nix`
- Delete: `packages/headroom-ai.nix`
- Modify: `modules/home-manager/default.nix:9-37`
- Modify: `modules/home-manager/opencode-work.nix:1-97`
- Modify: `users/adriel/linux-baseline.nix:14-47`
- Modify: `users/adriel-cachyos/default.nix:25-34`

**Interfaces:**
- Consumes: `local.opencode.extraSettings` from `modules/home-manager/opencode.nix`.
- Produces: plugin-only `local.opencode.llmPlatform` options and settings; no `local.headroom` option or systemd service.

- [ ] **Step 1: Capture the tracked removal surface**

Run:

```bash
rtk git grep -n -i headroom -- '*.nix'
```

Expected: matches only in the Headroom module/package, `modules/home-manager/default.nix`, `modules/home-manager/opencode-work.nix`, `users/adriel/linux-baseline.nix`, and `users/adriel-cachyos/default.nix`.

- [ ] **Step 2: Remove the shared module import and consumers**

Delete `./headroom.nix` from `modules/home-manager/default.nix`.

Delete these assignments from `users/adriel/linux-baseline.nix`:

```nix
local.headroom.enable = true;
HEADROOM_MODE = "token";
HEADROOM_INTERCEPT_ENABLED = "1";
```

Delete this assignment from `users/adriel-cachyos/default.nix`:

```nix
local.headroom.agents.opencode = true;
```

- [ ] **Step 3: Replace `opencode-work.nix` with direct plugin settings**

Use this complete module body:

```nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.opencode.llmPlatform;
  llmPlatformPlugin = "@reddit/opencode-llm-platform@https://artifactory.build.ue1.snooguts.net:443/artifactory/api/npm/reddit-npm-prod/%40reddit/opencode-llm-platform/-/opencode-llm-platform-0.0.2.tgz";

  llmPlatformSettings = lib.optionalAttrs cfg.enable (
    {
      share = "disabled";
      plugin = [ cfg.plugin ];
    }
    // lib.optionalAttrs (cfg.defaultModel != null) {
      model = cfg.defaultModel;
    }
  );
in
{
  options.local.opencode.llmPlatform = {
    enable = lib.mkEnableOption "Reddit LLM Platform OpenCode plugin";

    plugin = lib.mkOption {
      type = lib.types.str;
      default = llmPlatformPlugin;
      description = "OpenCode plugin spec for Reddit's LLM Platform provider.";
    };

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "llmplatform/claude-opus-4-8";
      description = "Default OpenCode model when the LLM Platform plugin is enabled.";
    };
  };

  config = lib.mkIf config.local.opencode.enable {
    local.opencode.extraSettings = llmPlatformSettings;
  };
}
```

This deliberately removes `upstreamBaseUrl`, `local.headroom.agents.opencode`, proxy headers, proxy provider overrides, and the cross-option assertion.

- [ ] **Step 4: Delete the package and service modules**

Delete:

```text
modules/home-manager/headroom.nix
packages/headroom-ai.nix
```

- [ ] **Step 5: Verify Nix references are gone before evaluation**

Run:

```bash
rtk git grep -n -E 'local\.headroom|HEADROOM_|x-headroom-|headroom-ai|headroom-proxy' -- '*.nix'
```

Expected: no matches.

### Task 2: Clean Repository Policy And Resolve The Exception

**Files:**
- Modify: `AGENTS.md:43-46,65,106`
- Modify: `TODO.md:5,18`

**Interfaces:**
- Consumes: the measured 4.6 percent proxy reduction and recorded Framework resource usage.
- Produces: generic RTK guidance and a historical resolved-exception record with no active Headroom follow-up.

- [ ] **Step 1: Remove the Headroom agent-integration policy**

Delete the complete `## Keep AI CLI token-saving reversible` section and its three bullets from `AGENTS.md`.

Keep the RTK instruction body unchanged, but rename its comments:

```markdown
<!-- rtk-instructions -->
...
<!-- /rtk-instructions -->
```

- [ ] **Step 2: Resolve the active Headroom exception**

Remove the active `Local headroom-ai 0.31.0 wheel package` entry from `Pinned exceptions to revisit`.

Replace the older resolved Headroom transport-patch entry with one consolidated resolved record under `Resolved pinned exceptions`:

```markdown
- 2026-07-10: removed the local Headroom 0.31.0 package, Home Manager proxy service, OpenCode routing overrides, and obsolete Codex transport patch history from active configuration. Original issue: Headroom was pinned outside Nixpkgs to compress AI-agent context, and earlier releases required a local Codex HTTP fallback because WebSocket Responses traffic bypassed compression. Upstream 0.31.0 removed the transport-patch need, but Framework measurements showed only a 4.6 percent whole-request proxy reduction while the service used about 1 GB RSS, roughly 82 percent of one CPU core, and repeatedly skipped Kompress work under ONNX saturation. Resolution: OpenCode now uses the LLM Platform plugin directly; all `local.headroom` options, service declarations, package derivations, routing headers, and Headroom environment variables are removed. Independent RTK command filtering remains enabled. Affected outputs: `homeConfigurations.adriel`, `homeConfigurations.cachyos-framework13`, `nixosConfigurations.razer14`, and `nixosConfigurations.dell`. Validation: all four exact output evaluations returned derivation paths, and tracked Nix configuration contains no `local.headroom`, `HEADROOM_`, `x-headroom-`, `headroom-ai`, or `headroom-proxy` references.
```

- [ ] **Step 3: Verify only intentional historical references remain**

Run:

```bash
rtk git grep -n -i headroom -- ':!docs/**'
```

Expected: the consolidated resolved `TODO.md` record is the only match.

Run:

```bash
rtk git grep -n 'rtk-instructions' AGENTS.md
rtk git grep -n 'home.packages = \[ pkgs.rtk \];' modules/home-manager/rtk.nix
```

Expected: generic RTK markers and the independent RTK package declaration are present.

### Task 3: Evaluate Every Affected Output

**Files:**
- Verify only; no additional edits expected.

**Interfaces:**
- Consumes: completed runtime and policy removal from Tasks 1-2.
- Produces: read-only evaluation evidence for all affected standalone and embedded Home Manager configurations.

- [ ] **Step 1: Confirm Headroom options and service are absent from Framework evaluation**

Run:

```bash
rtk nix eval --impure --expr 'let f = builtins.getFlake (toString ./.); c = f.homeConfigurations.cachyos-framework13.config; in { hasHeadroomOption = builtins.hasAttr "headroom" c.local; hasHeadroomService = builtins.hasAttr "headroom-proxy" c.systemd.user.services; hasProxyProviderOverride = builtins.hasAttr "provider" c.local.opencode.extraSettings; }'
```

Expected:

```nix
{ hasHeadroomOption = false; hasHeadroomService = false; hasProxyProviderOverride = false; }
```

- [ ] **Step 2: Evaluate standalone Home Manager outputs**

Run:

```bash
rtk nix eval .#homeConfigurations.adriel.activationPackage.drvPath
rtk nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
```

Expected: each command exits zero and returns one derivation path.

- [ ] **Step 3: Evaluate embedded NixOS Home Manager outputs**

Run:

```bash
rtk nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
rtk nix eval .#nixosConfigurations.dell.config.system.build.toplevel.drvPath
```

Expected: each command exits zero and returns one derivation path.

- [ ] **Step 4: Inspect final diff and concurrent worktree state**

Run:

```bash
rtk git status --short
rtk git diff -- AGENTS.md TODO.md modules/home-manager/default.nix modules/home-manager/opencode-work.nix users/adriel/linux-baseline.nix users/adriel-cachyos/default.nix modules/home-manager/headroom.nix packages/headroom-ai.nix
```

Expected: only the approved Headroom-removal edits plus the two new task documents are attributable to this task; no unrelated concurrent changes are reverted or modified.

- [ ] **Step 5: Report activation boundary**

Report that configuration evaluation passed, the currently running `headroom-proxy.service` remains active because no switch was authorized, and the service/package will disappear only after the user later activates the Home Manager configuration.
