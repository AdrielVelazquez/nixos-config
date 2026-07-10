# Headroom Removal Design

## Goal

Remove Headroom from every exported Linux user configuration while retaining the independent RTK command-output filtering module and instructions.

## Motivation

On `framework13`, Headroom 0.31.0 reduced proxy input by 4.6 percent over the measured 24-hour window. The active service used about 1 GB RSS, accumulated CPU time equivalent to roughly 82 percent of one core, and repeatedly skipped Kompress work because its ONNX execution slot was saturated. The configured `agent-90` profile applies a 10 percent keep ratio only to eligible text units; it does not promise a 90 percent reduction of the complete request. Most OpenAI Responses units were too small, protected, unchanged, or rejected, so the measured whole-request reduction is expected.

RTK remains useful and independent. Its command-output filtering reported 60.6 percent lifetime savings and does not require the Headroom proxy.

## Scope

Delete the local Headroom package, patch, and Home Manager module. Remove the module import, all `local.headroom` assignments, Headroom session variables, and Headroom-specific repository policy and pinned-exception entries.

Simplify the OpenCode module by removing Headroom routing state, proxy URLs, forwarding headers, the Headroom assertion, and the `llmPlatform.upstreamBaseUrl` option that exists only for proxy reconstruction. Keep the Reddit LLM Platform plugin and direct provider behavior unchanged.

Preserve `modules/home-manager/rtk.nix` and the RTK command guidance in `AGENTS.md`, but remove Headroom-specific framing or marker names around that guidance.

Do not modify existing untracked documentation or unrelated work from the concurrent agent. This design file is the only new documentation file for this task.

## Resulting Data Flow

OpenCode will load the configured LLM Platform plugin and send inference requests directly to the provider endpoints supplied by that plugin. No local proxy service, `x-headroom-*` routing headers, or Headroom package will be present.

Codex, Gemini, and Antigravity remain installed through their existing modules. None gains a replacement proxy integration. RTK continues to filter supported shell command output before it enters agent context.

## Cleanup Semantics

Home Manager activation after this change will stop declaring `headroom-proxy.service` and remove the Headroom package from the active profile. No command that changes the running system will be executed during implementation. Existing runtime state under `~/.headroom` is user data and will not be deleted automatically.

Historical performance logs and state therefore remain available until the user chooses to remove them manually.

## Validation

The removal affects both standalone Home Manager outputs and NixOS outputs embedding the shared user configuration. Run these read-only evaluations:

```bash
nix eval .#homeConfigurations.adriel.activationPackage.drvPath
nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.dell.config.system.build.toplevel.drvPath
```

Also search tracked configuration for remaining `headroom`, `HEADROOM_`, `local.headroom`, and `x-headroom-` references. Remaining references are acceptable only in this removal record or resolved historical documentation that is intentionally retained.

No `home-manager switch`, `nixos-rebuild switch`, or other activation command is part of this task.
