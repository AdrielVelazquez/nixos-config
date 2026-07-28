# Configuration Hardening Strict-Cutover Design

## Goal

Make every flake output and operational recipe identify its target explicitly,
remove surprising host mutation from system-manager activation, restore normal
Nix defaults where local overrides are no longer justified, and keep
GPU-specific software on the Razer host that owns the GPU.

This is a strict naming cutover. Compatibility aliases are intentionally not
retained.

## Target and Validation Context

Target configs:

- `nixosConfigurations.razer14`
- `nixosConfigurations.dell-plex`
- `homeConfigurations.razer14`
- `homeConfigurations.cachyos-framework13`
- `systemConfigs.cachyos-framework13`
- `darwinConfigurations.PNH46YXX3Y`

Validation host: `framework13` running CachyOS Linux. NixOS and Darwin targets
will be evaluated from that host, not activated there.

Planned minimum verification:

```text
nix eval .#nixosConfigurations.razer14.config.system.build.toplevel.drvPath
nix eval .#nixosConfigurations.dell-plex.config.system.build.toplevel.drvPath
nix eval .#homeConfigurations.razer14.activationPackage.drvPath
nix eval .#homeConfigurations.cachyos-framework13.activationPackage.drvPath
nix eval .#systemConfigs.cachyos-framework13.drvPath
nix eval .#darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel.drvPath
```

The Framework system-manager derivation and the lightweight configuration
checks will also be built. No NixOS, Home Manager, system-manager, or Darwin
switch will run as part of implementation validation.

The existing user-owned `flake.lock` changes are outside this design and must
remain unstaged and unmodified.

## Canonical Output Names

The flake will expose one descriptive name for each configuration:

| Configuration kind | Current name | Canonical name |
| --- | --- | --- |
| Razer NixOS | `razer14` | `razer14` |
| Dell Plex NixOS | `dell` | `dell-plex` |
| Razer standalone Home Manager | `adriel` | `razer14` |
| Framework standalone Home Manager | `cachyos-framework13` | `cachyos-framework13` |
| Framework system-manager | `cachyos-framework` | `cachyos-framework13` |
| Reddit Mac Darwin | `PNH46YXX3Y` | `PNH46YXX3Y` |

All checks, documentation, TODO references, error messages, and recipes will use
the canonical names. The old `dell`, `adriel`, and `cachyos-framework` output
names will disappear, and no `default` output will replace them.

## Explicit `just` Targets

Generic recipes must require the target as an argument instead of asking Nix to
infer it from the current hostname or username:

- NixOS `switch`, `switch-trace`, `build`, `test`, `dry-run`, and `diff`
- Home Manager `home-switch` and `home-build`
- Darwin `darwin-switch` and `darwin-build`
- system-manager `system-manager-switch`

The named Framework convenience workflows may remain because their target is
encoded in the recipe name. Their commands must reference
`cachyos-framework13`.

Recipe validation will cover:

- `just --list`
- a dry run of every changed generic recipe with its canonical target
- a dry run of the Framework convenience recipes
- failure when a required target is omitted
- absence of the retired output names in emitted commands and help text

Dry runs only render commands; they do not activate a configuration.

## Orbit Package Ownership

System-manager must manage the Orbit service but must never silently uninstall
a native package during boot or activation.

The Orbit module will therefore remove:

- the `remove-native-orbit.service` unit
- its generated removal script
- the `removeNativePackage` option
- its ordering dependency from `orbit.service`
- all noninteractive `pacman -R --noconfirm` behavior

In its place, an enabled pre-activation assertion will detect any configured
native Arch Fleet package, currently `fleet-osquery`, and stop with a clear
migration message. This makes an ownership conflict visible before activation
without changing the host.

A separately invoked `just migrate-cachyos-orbit` recipe will perform the
one-time migration interactively. It will verify that the native package is
installed, stop the native Orbit service when present, invoke the native
`/usr/bin/pacman` removal command without `--noconfirm`, and reload systemd
after a successful removal. If the package is already absent, the recipe will
report that no migration is needed. This recipe is intentionally not a
dependency of switch or bootstrap recipes.

## Nix Defaults and Root Maintenance

The oversized `download-buffer-size` settings will be removed from both the
shared Linux profile and the Darwin host. Nix will use its upstream default
instead of maintaining local 640 MiB and roughly 1.56 GiB overrides.

The Framework system-manager configuration will also stop granting Nix trusted
user status to `@wheel` and `adriel`; omitting `trusted-users` restores the
effective root-only default.

Root Nix operations in the `justfile` must not depend on forwarding the caller's
`PATH` through `sudo`. They will invoke the root profile binaries directly:

- `/nix/var/nix/profiles/default/bin/nix`
- `/nix/var/nix/profiles/default/bin/nix-collect-garbage`
- `/nix/var/nix/profiles/default/bin/nix-store`

User-level Nix commands remain unchanged.

## Razer-Only CUDA `llama-cpp`

The CUDA-enabled `llama-cpp` package will move out of
`users/adriel/common.nix` and into `users/adriel/default.nix`, the Razer-specific
Home Manager wrapper. Dell will no longer receive `llama-cpp` from the shared
user configuration.

Both ways of evaluating the Razer user must use the same CUDA architecture:

- embedded Home Manager in `nixosConfigurations.razer14`
- standalone `homeConfigurations.razer14`

The standalone Home Manager package import will therefore set
`cudaCapabilities = [ "12.0" ]`, matching the Razer NixOS host override.
`12.0` is the RTX 5070 Laptop GPU's fixed CUDA compute capability, corresponding
to `sm_120`; it is not the CUDA toolkit version. Driver and toolkit upgrades do
not change this value. It should change only if the GPU hardware changes, or
expand to multiple capabilities if the same output deliberately needs to build
for additional GPUs.

The configuration contract will confirm that CUDA `llama-cpp` is present in
both Razer Home Manager evaluations, absent from the Dell user package set, and
compiled for `CMAKE_CUDA_ARCHITECTURES=120`.

The live hardware check for future migrations is:

```text
nvidia-smi --query-gpu=name,compute_cap --format=csv
```

## CPU and Memory Limits

No endpoint-agent CPU or memory limits will change in this batch.

Measurements on the Framework host showed that throttling is real but bursty:

| Service | Configured CPU quota | Throttled periods | Cumulative throttled time |
| --- | ---: | ---: | ---: |
| Falcon | 5% | 4,654 / 19,637 (23.7%) | about 276 seconds |
| Orbit | 20% | 40 / 6,084 (0.66%) | about 1 second |
| Duo | 0.25% | 7,412 / 7,654 (96.8%) | about 5,794 seconds |
| WARP | none | none | none |

A separate 15-second idle sample observed no sustained throttled time increase:
Falcon had one throttled period with no measurable throttled microseconds,
while Orbit and Duo had none. This supports retaining the caps until workload
impact can be measured rather than removing them based only on cumulative
counters.

Falcon also exceeded its 256 MiB `MemoryHigh` threshold repeatedly while
remaining below its 512 MiB `MemoryMax`; no OOM or hard-limit event occurred.
That is useful follow-up evidence but is not part of this change.

## Regression Contract

The existing evaluated configuration contract will be extended before the
implementation so it initially fails for the old behavior. It will cover:

- exact canonical output names and absence of retired/default aliases
- no boot-time or activation-time native Orbit removal unit
- an enabled native Fleet conflict assertion
- root-only Framework Nix trust
- absence of local `download-buffer-size` overrides
- Razer-only CUDA `llama-cpp` with architecture 120
- unchanged endpoint-agent CPU and memory policy

After implementation, exact output evaluations will be followed where
practical by:

- the Framework system-manager build
- the configuration-contract check
- formatting and lightweight repository checks
- `just --list` and dry-run recipe coverage
- searches for stale output names, aliases, `sudo env "PATH=$PATH"`, and
  automatic native Fleet removal behavior

Any evaluation failure will be diagnosed at the specific output before broader
checks continue. Activation remains a separate user-approved step.

## Migration Impact

Existing commands using `.#dell`, `.#adriel`, or
`.#cachyos-framework` will fail after the cutover. Their replacements are
`.#dell-plex`, `.#razer14`, and `.#cachyos-framework13`, respectively.

If native `fleet-osquery` is still installed, the next Framework
system-manager switch will intentionally stop at the pre-activation assertion.
The user must run `just migrate-cachyos-orbit` and approve the native package
removal before retrying the switch.

No automatic service restarts, package removals, or configuration activations
are included in the implementation phase.
