# Framework Configuration Hardening Design

Date: 2026-07-30

## Context

The Framework 13 CachyOS configuration currently evaluates and runs, but five
areas are harder to reason about than they need to be:

1. Steam is present while the system graphics bridge exports only the 64-bit
   driver tree.
2. The non-NixOS host does not share the binary-cache policy or automated Nix
   maintenance used by the NixOS hosts.
3. Docker and Steam are installed by both system-manager and Home Manager, with
   the system-manager copies shadowing the Home Manager copies at runtime.
4. Orbit's enrollment-secret option accepts a Nix path value even though the
   credential must remain a runtime path outside the Nix store.
5. The Justfile distinguishes evaluation-only and full flake checks, but does
   not provide a curated inexpensive build check or direct system-manager
   evaluation/build recipes.

The primary targets are `systemConfigs.cachyos-framework13` and
`homeConfigurations.cachyos-framework13`. The validation machine is the
Framework 13 running CachyOS Linux. Orbit's option contract is also shared with
NixOS consumers and must remain safe there.

## Goals

- Export both 64-bit and 32-bit Mesa drivers for the Framework Steam runtime.
- Reuse one binary-cache policy across NixOS and system-manager.
- Run bounded, low-priority Nix maintenance on the Framework each week.
- Give each large application one clear configuration owner.
- Make it impossible to configure Orbit with a Nix path literal or a path under
  `/nix/store`.
- Add useful Justfile validation entry points without changing the meaning of
  existing recipes.
- Prove the behavior with focused regression checks and exact output
  evaluation.

## Non-goals

- Activating or switching Home Manager or system-manager.
- Running garbage collection during development or validation.
- Changing CUDA packages, CUDA architectures, or CUDA-heavy checks.
- Enabling automatic maintenance on Razer, Dell, Darwin, or other
  system-manager targets.
- Updating flake inputs unless the required TODO audit identifies an upstream
  resolution that is both directly relevant and safe to adopt separately.

## Considered Approaches

### A. Shared policy with host-scoped activation

Extract reusable cache settings, add a reusable system-manager maintenance
module, and enable maintenance and 32-bit graphics only on Framework. Keep
Docker and Steam ownership explicit at their natural layers.

This adds a small amount of module structure, but it avoids duplicated cache
keys and keeps host-specific behavior host-specific. This is the selected
approach.

### B. Framework-local configuration

Place cache settings, timer units, and all graphics overrides directly in the
Framework host file.

This has the smallest initial diff, but duplicates the NixOS cache policy and
makes later key or endpoint changes easy to apply inconsistently.

### C. Global maintenance convergence

Create one maintenance policy and enable it for every Linux host.

This is superficially uniform but broadens the operational change to machines
that were not measured or requested. It also obscures the distinction between
native NixOS maintenance options and the units needed on CachyOS.

## Design

### Shared cache policy

A small shared Nix module will own the substituter URLs and trusted public
keys. The existing NixOS base profile and the system-manager base module will
import it.

The NixOS result must remain semantically unchanged. The Framework will gain
the same cache list:

- `https://cache.nixos.org`
- `https://nix-community.cachix.org`
- `https://cuda-maintainers.cachix.org`
- `https://niri.cachix.org`

The corresponding trusted keys will move with the URLs so the two lists cannot
silently drift between configuration systems.

### Framework graphics

The generic system-manager graphics bridge will explicitly select `pkgs.mesa`
and `pkgs.pkgsi686Linux.mesa`. These are the non-deprecated package paths that
currently resolve to the same Mesa driver packages as the deprecated
`mesa.drivers` aliases.

Only `systemConfigs.cachyos-framework13` will enable the 32-bit graphics tree.
After activation by the user in a later step, this is expected to provide
`/run/opengl-driver-32`, which the Nix Steam wrapper already searches.

### Framework Nix maintenance

A reusable system-manager module will expose a disabled-by-default
`local.nix-maintenance` option set. Framework will enable it with:

- weekly garbage collection;
- profile-generation retention of 14 days;
- weekly store optimisation;
- persistent timers so a missed laptop schedule can run after the next boot;
- a randomized delay to avoid immediate boot-time contention; and
- idle CPU/I/O scheduling with a high nice value.

The garbage-collection command will use Nix's standard
`--delete-older-than 14d` behavior. Precisely, this deletes profile generations
older than 14 days and then collects store paths that are no longer reachable
from a root; it does not apply an independent 14-day age test to every
unreachable store path.

Garbage collection and optimisation will use separate service units and
non-overlapping weekly schedules. Failures will remain visible through the
normal systemd unit status and journal. No maintenance command will run as part
of evaluation, build, test, or this implementation session.

### Package ownership

Package ownership will be:

- Docker daemon and Docker CLI: system-manager.
- Steam client: Home Manager.
- 32-bit graphics runtime support: system-manager.

The Framework system-manager host package list will stop installing Steam.
The Framework Home Manager package list will stop installing Docker. Existing
Docker daemon configuration and Home Manager Steam configuration will remain
otherwise unchanged.

This removes the shadowed duplicate revisions while preserving the commands
the user expects after the next approved switches.

### Orbit secret-path contract

Both Orbit modules will change `enrollSecretPath` from a Nix path option to an
optional absolute runtime string. Evaluation will reject:

- relative strings;
- Nix path literals such as `./secret`; and
- strings rooted under `/nix/store`.

The active value remains `/run/secrets/fleet_enroll_secret`. systemd continues
to receive that value through `LoadCredential`, and Orbit continues to read the
credential through `%d/enroll-secret`. Secret contents remain outside
derivations, generated scripts, and the Nix store.

Focused module-evaluation coverage will demonstrate that an absolute `/run`
string succeeds while path literals and store paths fail.

### Justfile validation interface

Existing recipe behavior will be preserved:

- `just check` remains evaluation-only.
- `just check-build` remains the full flake build path.
- existing switch recipes retain their names and behavior.

New recipes will be added:

- `just check-fast` builds a curated set of inexpensive repository checks.
- `just system-manager-eval CONFIG` evaluates the selected system-manager
  derivation path.
- `just system-manager-build CONFIG` builds the selected system-manager output
  without creating a result symlink or activating it.

The fast recipe will exclude CUDA-heavy host builds. Invalid configuration
names or failed checks will propagate the underlying Nix failure rather than
being hidden by shell wrappers.

## Testing and Validation

Implementation will begin with focused failing regression tests for the new
contracts, followed by the smallest configuration changes that make them pass.
Coverage will include:

- Framework 32-bit graphics and explicit Mesa package selection;
- shared cache URLs and keys;
- maintenance timer schedules, retention command, persistence, and
  low-priority service settings;
- absence of system-manager Steam and Home Manager Docker duplication;
- acceptance and rejection cases for Orbit secret paths; and
- dry-run/contract coverage for every new Justfile recipe.

The minimum final validation is:

```text
nix eval .#systemConfigs.cachyos-framework13.drvPath
nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
```

It will be followed, where practical, by focused check builds,
`just check-fast`, the non-activating system-manager build recipe, and
`just check`. CUDA-heavy full-host builds remain outside the fast validation
path. No switch, activation, or garbage collection is authorized by this
design.

## Rollback

Each behavior is independently reversible:

- disable Framework 32-bit graphics and remove the explicit package
  selections;
- disable `local.nix-maintenance` while leaving the reusable module inert;
- restore the prior Docker and Steam package entries;
- restore the prior Orbit option type; or
- remove the new Justfile recipes.

The cache-policy extraction can be inlined back into the NixOS base profile
without changing its values.
