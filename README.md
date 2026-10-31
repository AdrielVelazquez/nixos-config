# Nix Configuration

Linux flake for the Razer Blade 14 and Framework 13. Razer runs NixOS;
Framework can keep its CachyOS/System Manager setup or migrate later to the
native `framework-work` NixOS host. Both NixOS hosts embed Home Manager;
CachyOS retains separate system and user activation boundaries. Reusable
behavior lives under `modules/`, wired explicitly in `flake.nix`.

For a small reference configuration, see [`examples/minimal/`](./examples/minimal/).

## Exported Configurations

| Flake output | Names |
|---|---|
| `nixosConfigurations` | `razer14`, `framework-work` |
| `homeConfigurations` | `cachyos-framework13` |
| `systemConfigs` | `cachyos-framework13` |

The directory names are not always the same as the exported names. Use the
flake output names above when running build or activation commands.

## Repository Layout

```text
flake.nix                              Inputs and explicit flake outputs
flake.lock                             Pinned input revisions
checks.nix                             Output and source regression checks
justfile                               Local build, validation, and activation recipes
hosts/razer14/                         Razer Blade 14 NixOS configuration
hosts/framework-work/                  Native encrypted Framework work NixOS host
hosts/cachyos-framework13-system-manager/  Framework 13 system-manager configuration
users/adriel/                          Home Manager config embedded in Razer NixOS
users/adriel-cachyos/                  Standalone Framework Home Manager config
users/adriel-work/                     Shared Framework work profile, login remains adriel
modules/home-manager/                  Reusable user and desktop modules
modules/profiles/                       Shared system profiles
modules/services/                       Reusable NixOS service modules
modules/shared/                         Cross-boundary Nix settings and helpers
modules/system/                         Reusable NixOS modules
modules/system-manager/                 Reusable non-NixOS Linux modules
packages/                               Locally packaged software
dotfiles/                               Application configuration
assets/                                 Static configuration assets
docs/                                   Design notes and troubleshooting guides
examples/minimal/                       Small direct-output NixOS reference flake
secrets/secrets-enc.yaml                SOPS-encrypted secrets
tests/                                  Source and command-contract tests
```

The repository does not use a `parts/` assembly layer. `flake.nix` declares
the active `nixosConfigurations`, `homeConfigurations`, and `systemConfigs`
directly, while each output imports reusable modules and one host or user entry
point. This keeps exported names visible in one place without moving reusable
behavior out of `modules/`.

The NixOS outputs combine the host and Home Manager user into one activation
boundary. CachyOS deliberately keeps its host and Home Manager outputs
separate. Both Framework alternatives import `users/adriel-work`; only the
CachyOS wrapper selects host-native hyprlock.

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
just build HOST                   # Build a NixOS configuration
just dry-run HOST                 # Dry-build a NixOS configuration
just bootstrap-dry razer14        # Fresh-install-compatible NixOS dry-build
just home-build CONFIG            # Build a Home Manager configuration
just diff HOST                    # Build and compare with /run/current-system
```

### State-Changing Activation

Review diffs and target names before running these commands:

```bash
just switch HOST                           # Switch NixOS configuration
just switch-trace HOST                     # Switch NixOS with an evaluation trace
just test HOST                             # Temporarily activate NixOS until reboot
just rollback                              # Switch to the previous NixOS generation
just switch-generation 42                  # Activate generation 42
just home-switch CONFIG                    # Switch Home Manager configuration
just home-activate cachyos-framework13      # Activate Home Manager through nix run
just home-activate-cachyos                  # Activate cachyos-framework13 Home Manager
just system-manager-switch CONFIG           # Switch a system-manager configuration
```

### Bootstrap

Bootstrap recipes are state-changing and may require root privileges:

```bash
just bootstrap razer14             # Switch NixOS from a fresh installation
just bootstrap-home cachyos-framework13  # Activate Home Manager without its CLI
just bootstrap-cachyos-prereqs     # Install Framework's native host prerequisites
just bootstrap-cachyos             # Switch Framework system-manager and Home Manager
```

The Framework system-manager recipes run `.#system-manager`, the application
provided by this flake's locked `system-manager` input, rather than a floating
upstream command. The full bootstrap first installs native CachyOS PAM/D-Bus
prerequisites; ordinary system-manager activation only verifies them and never
runs the host package manager.

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
- [Framework work laptop on NixOS](./hosts/framework-work/README.md) — fresh encrypted installation and migration blockers
- [Framework 13 Apple Studio Display troubleshooting](./docs/troubleshooting/framework13-apple-studio-display.md)

## Fresh NixOS Installation

Both NixOS hosts use host-local Disko configurations. Partitioning and
installation destroy data or replace the running system. Follow the
[Framework NixOS guide](./hosts/framework-work/README.md) for explicit disk
selection, credentials, installation steps, and workplace migration gates.
Build/evaluate first; `just bootstrap HOST` switches an existing system and
is not a disk installer.
