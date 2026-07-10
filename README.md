# Nix Configuration

Multi-platform flake for NixOS, nix-darwin, standalone Home Manager, and
system-manager hosts. The repository is organized with flake-parts and reusable
modules under `modules/`.

For a small reference configuration, see [`examples/minimal/`](./examples/minimal/).

## Exported Configurations

| Flake output | Names |
|---|---|
| `nixosConfigurations` | `razer14`, `dell` |
| `darwinConfigurations` | `PNH46YXX3Y` |
| `homeConfigurations` | `adriel`, `cachyos-framework13` |
| `systemConfigs` | `cachyos-framework`, `default` |

The directory names are not always the same as the exported names. Use the
flake output names above when running build or activation commands.

## Repository Layout

```text
flake.nix                         Flake entry point and inputs
flake.lock                        Pinned input revisions
justfile                          Local command runner
parts/                            Flake-parts output definitions and checks
hosts/                            Host-specific configuration
users/                            Home Manager configuration wrappers
modules/system/                   Reusable NixOS modules
modules/services/                 Reusable NixOS service modules
modules/home-manager/             Reusable Home Manager modules
modules/system-manager/           Reusable non-NixOS Linux modules
modules/mac-services/             Reusable nix-darwin service modules
modules/profiles/                 Shared system profiles
dotfiles/                         Application configuration
secrets/secrets-enc.yaml          SOPS-encrypted secrets
tests/                            Source regression tests
```

Important host paths:

- `hosts/razer14/`: Razer Blade 14 NixOS configuration.
- `hosts/dell-plex-server/`: Dell Plex server NixOS configuration exported as
  `dell`.
- `hosts/reddit-mac/`: nix-darwin configuration exported as `PNH46YXX3Y`.
- `hosts/cachyos-framework13-system-manager/`: Framework 13 CachyOS
  system-manager configuration.

## Local Validation

Hosted CI is not configured. Complete flake evaluation requires private
SSH-backed inputs, and an unauthenticated hosted runner does not have the
credentials needed to fetch and evaluate every output.

Run validation locally from a checkout with access to those inputs:

```bash
just check        # Evaluate all checks for the current system without building
just check-build  # Build all checks for the current system
```

Full configuration builds can be expensive, particularly for CUDA-enabled
hosts. Build a specific output when needed instead of treating every full build
as a lightweight lint step.

## Commands

Run `just --list` for the authoritative recipe list. Commands that activate a
configuration, alter boot/system state, update locks, or delete store data are
called out below.

### Inspection And Validation

```bash
just                       # List recipes
just check                 # Evaluate current-system checks without building
just check-build           # Build current-system checks
just info                  # Show flake outputs
just inputs                # Show locked input names
just eval nixosConfigurations.razer14.config.system.stateVersion
just repl                  # Open a Nix REPL with the flake loaded
just list-hosts            # List NixOS outputs
just list-homes            # List Home Manager outputs
just generations           # List system generations (read-only, uses sudo)
```

`just fmt` modifies Nix and Lua source files in place.

### Build Without Activation

```bash
just build [host]                 # Build a NixOS configuration
just dry-run [host]               # Dry-build a NixOS configuration
just bootstrap-dry razer14        # Fresh-install-compatible NixOS dry-build
just darwin-build [host]          # Build the Darwin configuration
just home-build [config]          # Build a Home Manager configuration
just diff [host]                  # Build and compare with /run/current-system
```

### State-Changing Activation

Review diffs and target names before running these commands:

```bash
just switch [host]                         # Switch NixOS configuration
just switch-trace [host]                   # Switch NixOS with an evaluation trace
just test [host]                           # Temporarily activate NixOS until reboot
just rollback                              # Switch to the previous NixOS generation
just switch-generation 42                  # Activate generation 42
just darwin-switch [host]                  # Switch nix-darwin configuration
just home-switch [config]                  # Switch Home Manager configuration
just home-activate cachyos-framework13      # Activate Home Manager through nix run
just home-activate-cachyos                  # Activate cachyos-framework13 Home Manager
just system-manager-switch [config]         # Switch a system-manager configuration
```

### Bootstrap

Bootstrap recipes are state-changing and may require root privileges:

```bash
just bootstrap razer14             # Switch NixOS from a fresh installation
just bootstrap-home cachyos-framework13  # Activate Home Manager without its CLI
just bootstrap-cachyos             # Switch Framework system-manager and Home Manager
```

The Framework system-manager recipes run `.#system-manager`, the application
provided by this flake's locked `system-manager` input, rather than a floating
upstream command.

### Input And Store Maintenance

These commands change `flake.lock` or local Nix state:

```bash
just update                         # Update every flake input
just update-input home-manager      # Update one flake input
just gc                             # Delete old user and system generations
just gc-older [days]                # Delete generations older than N days
just optimize                       # Deduplicate the Nix store
just clean                          # Run garbage collection and optimization
```

Prefer `just update-input INPUT` to avoid unrelated lock-file churn.

## Secrets

Only encrypted files matching `secrets/*-enc.yaml` or
`secrets/*-enc.yml` belong in Git. `.sops.yaml` contains the public age
recipient used for new encrypted files. Private age keys and decrypted values
must remain outside the repository and must not be interpolated into the Nix
store.

Check encryption status without writing decrypted content into the checkout:

```bash
sops filestatus secrets/secrets-enc.yaml
```

## Host Guides

- [Framework 13 on CachyOS](./hosts/cachyos-framework13-system-manager/README.md)
- [Framework 13 Apple Studio Display troubleshooting](./docs/troubleshooting/framework13-apple-studio-display.md)

## Fresh NixOS Installation

The Razer host uses Disko from `hosts/razer14/disko.nix`. Partitioning and
bootstrap operations can destroy data or replace the running system. Inspect
the host configuration and use `just bootstrap-dry razer14` before any
state-changing installation command.
