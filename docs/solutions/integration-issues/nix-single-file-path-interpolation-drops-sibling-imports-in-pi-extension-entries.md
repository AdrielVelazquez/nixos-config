---
title: A Nix single-file path interpolation drops sibling imports from a Pi extension entry, and eval cannot see it
date: 2026-10-24
last_updated: 2026-10-29
category: integration-issues
module: modules/home-manager/pi/ui.nix
problem_type: integration_issue
component: tooling
symptoms:
  - "Pi starts with its native UI and prints Failed to load extension ... Cannot find module './opencode-ui-core.ts'"
  - "nix eval and nix build of the home activation package both succeed"
  - "A sandbox check that runs a script from the store fails with a missing sibling file such as /nix/store/fixture.ts"
root_cause: config_error
resolution_type: code_fix
severity: medium
tags: [nix, pi, extensions, jiti, store-path, home-manager, checks]
---

# A Nix single-file path interpolation drops sibling imports from a Pi extension entry, and eval cannot see it

## Problem

`"${../../dotfiles/pi/extensions/opencode-ui.ts}"` in a Nix string copies only that one file to the store. Pi loads the generated entry through jiti from the store path, so the extension's `import ... from "./opencode-ui-core.ts"` has nothing next to it. The skin silently did not load and Pi fell back to its native UI.

## Symptoms

- The managed `pi` shows `Failed to load extension ".../pi-opencode-ui.ts": Cannot find module './opencode-ui-core.ts'` and then looks stock.
- `nix eval` of the activation package and `nix build` of it pass; only a real Pi load shows the failure.
- The same mistake in `checks/pi-ui.nix` (`${../tests/pi/ui-preview/preview.py}`) left `fixture.ts` unreachable. The script ignored its first failed `wait()`, kept going and ended on the 240 s `timeout` with exit 124 and no message.

## What Didn't Work

- Trusting `nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath`. Entry files are `writeText` re-exports; the drvPath proves they build, not that the TypeScript they point at resolves.
- Stopping at the first failure. A preview of the generated settings first reported `Extension path does not exist` because evaluation had not realised the entry; building the activation package fixed that and only then exposed the missing-sibling error.

## Solution

Interpolate the directory and name the file after it, as `pi-ghost.nix` already does (`${../../dotfiles/pi/extensions}/ghost-text.ts`):

```nix
opencodeEntry = pkgs.writeText "pi-opencode-ui.ts" ''
  export { default } from "${../../dotfiles/pi/extensions}/opencode-ui.ts";
'';
```

and `python3 ${../tests/pi/ui-preview}/preview.py` for scripts that read neighbours. A file with no sibling imports (`neutral-foreground.ts`) works either way, which is how the single-file form survives review.

## Scoped test sources and generated imports

Prefer scoped filesets in `checks/sources.nix` over copying the whole repository, but audit imports inside generated strings as well as ordinary import declarations. `tests/pi/routing.mjs` writes a child-policy module that imports `dotfiles/pi/extensions/required-integrations.ts` using a working-directory-relative path embedded in a template string.

Omitting that helper from the scoped routing source passed evaluation and the static import audit, but the real nested-entry test failed with `nested entry evidence` and a message about unavailable fixture MCP tools. The same fixture passed with the whole-repository working directory. Adding the helper to the routing fileset restored the full runtime check without changing its assertions or weakening MCP policy.

A missing source can therefore masquerade as a routing or capability-registration failure rather than an obvious missing-file error. Preserve the relative layout, inspect generated fixture code and run the real consumer. Keep whole subdirectories where dynamic discovery or negative-presence checks genuinely need them; do not narrow such checks into vacuous passes.

## Why This Works

A path used as a string is imported into the store as the path itself, so a file yields a lone store file while a directory yields the whole tree. Relative imports and `here / "fixture.ts"` lookups then resolve inside that copy.

## Prevention

- After adding or changing a Pi extension entry, build the generated configuration and load it in a real Pi, not just evaluate it. `tests/pi/ui-preview/preview.py --settings <generated settings.json>` does this headlessly, and `pi-ui-opencode` runs it in the sandbox.
- Test scripts that wait on a real process should fail on the first timeout and print the screen; a silent fall-through turned a one-line path error into a four-minute hang.

## Related Issues

- `docs/solutions/tooling-decisions/nix-flake-drvpath-is-not-a-refactor-proof.md`: the same limit of eval-only validation.
