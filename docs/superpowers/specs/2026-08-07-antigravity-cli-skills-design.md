# Antigravity CLI Skill Discovery Design

## Goal

Make the configured Superpowers skills discoverable by Antigravity CLI and
restore the moved `agp-9-upgrade` Android skill without changing the skill
behavior for Gemini CLI, Codex, or OpenCode.

## Target and validation

- Target config: `homeConfigurations.razer14`
- Validation host: `razer14` / NixOS
- Required verification:
  `nix eval .#homeConfigurations.razer14.activationPackage.drvPath`
- Shared-module verification:
  `nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath`
- Activation is out of scope. `home-manager switch` requires separate explicit
  approval under the repository policy.

## Root causes

The Antigravity target writes skills below
`~/.gemini/antigravity/skills`, which Antigravity CLI does not scan. The CLI
advertises `~/.gemini/antigravity-cli/skills` as its global skill root.
Superpowers therefore has no copy in an Antigravity CLI discovery root, even
though its managed source links and `SKILL.md` frontmatter are valid.

The Android skills input also moved `agp-9-upgrade` from
`build/agp/agp-9-upgrade` to `build-system/agp/agp-9-upgrade`. The stale path
produces a broken Home Manager link, so the skill is absent from the CLI's
discovered list.

## Design

Change only the reusable Home Manager skill module and its configuration
contract:

1. Replace the Antigravity discovery root with
   `.gemini/antigravity-cli/skills` everywhere it is generated or cleaned.
2. Generate Antigravity's Superpowers entries recursively. Home Manager will
   create real skill directories containing managed links, matching the
   structure already used by the working shared Android skills.
3. Change the `agp-9-upgrade` source mapping to
   `build-system/agp/agp-9-upgrade`.
4. Leave the Gemini extension, Codex skill root, OpenCode skill root, and all
   other Android mappings unchanged.

The old `.gemini/antigravity/skills` declarations will disappear from the new
Home Manager generation. A later approved activation will reconcile the live
home directory with that generation.

## Regression coverage

Extend the existing configuration contract in `parts/checks.nix`. The contract
will require the standalone Razer Home Manager configuration to:

- declare `.gemini/antigravity-cli/skills/using-superpowers`;
- mark that entry recursive;
- declare `.gemini/antigravity-cli/skills/agp-9-upgrade` with an existing
  source path; and
- omit `.gemini/antigravity/skills/using-superpowers`.

The test is added before the implementation and must fail for the current
unsupported path. After the minimal module edit, the configuration contract and
both Linux Home Manager activation-package evaluations must succeed.

## Scope and exceptions

This change follows current upstream input contents and Antigravity CLI's
documented discovery path. It adds no package pin, fork, patch, secret, or
runtime-system exception, so it does not require a new `TODO.md` entry. Existing
untracked files and unrelated repository changes remain untouched.
