# NixOS Configuration

Personal NixOS, Darwin, and Home Manager configuration flake.

## Quick Start

Most commands are available through `just`. Run `just` to see all available commands.

```bash
just          # Show all available commands
just --list   # Same as above
```

## Prerequisites

### Starting from Scratch (New NixOS Install)

Add the following to `/etc/nixos/configuration.nix`:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

Run `sudo nixos-rebuild switch` to enable flakes.

**Note:** Copy your `hardware-configuration.nix` into the appropriate host directory. Don't reuse old hardware configs as variables may have changed.

## Common Commands

### NixOS Systems

```bash
# Rebuild and switch (auto-detects hostname)
just switch

# Rebuild specific host
just switch razer14
just switch dell
just switch reddit-framework13

# Test without making permanent (reverts on reboot)
just test

# Dry-run to see what would change
just dry-run

# Show diff between current and new config
just diff
```

### macOS (Darwin)

```bash
just darwin-switch
just darwin-build
```

### Home Manager

```bash
# With home-manager CLI installed
just home-switch
just home-switch adriel

# Without home-manager CLI (non-NixOS systems)
just home-activate reddit-framework13
just home-activate-reddit  # Shortcut for above
```

### Non-NixOS Linux (System Manager)

```bash
just system-manager-switch
```

## Maintenance

```bash
just update           # Update all flake inputs
just update-input nixpkgs  # Update specific input
just gc               # Garbage collect old generations
just gc-older 7       # GC generations older than 7 days
just clean            # Full cleanup: gc + optimize
just generations      # List system generations
```

## Development

```bash
just fmt              # Format all Nix files
just check            # Validate flake
just info             # Show flake info
just repl             # Open nix repl with flake loaded
just dev              # Enter default dev shell
just dev-python       # Enter Python dev shell
```

## Directory Structure

```
~/.nixos/
├── flake.nix              # Main flake definition
├── flake.lock             # Locked dependencies
├── justfile               # Command runner recipes
├── hosts/                 # Host-specific configurations
│   ├── razer14/
│   ├── dell-plex-server/
│   ├── reddit-framework13/
│   └── reddit-mac/
├── modules/
│   ├── home-manager/      # User-level modules (local.*)
│   ├── nixos/             # Shared NixOS configuration
│   ├── services/          # Service modules
│   └── system/            # System-level modules (local.*)
├── users/                 # User configurations
│   ├── common.nix         # Shared user settings
│   ├── adriel.nix
│   └── adriel.velazquez.*.nix
├── secrets/               # SOPS-encrypted secrets
│   └── secrets-enc.yaml
├── lib/                   # Shared functions and metadata
└── dotfiles/              # Application configs (nvim, kitty, etc.)
```

## Available Hosts

| Host | System | Description |
|------|--------|-------------|
| `razer14` | NixOS | Razer Blade 14 laptop |
| `dell` | NixOS | Dell Plex server |
| `reddit-framework13` | NixOS | Reddit Framework 13 laptop |
| `PNH46YXX3Y` | Darwin | Reddit MacBook |

## Secrets Management

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix).

```bash
sops-check    # Check sops configuration
sops-edit     # Edit secrets file
sops-view     # View decrypted secrets
```

## SSH with Private Repos

If you get errors pulling private repos during rebuild:

```bash
# Pass SSH agent to root
sudo SSH_AUTH_SOCK=$SSH_AUTH_SOCK nixos-rebuild switch --flake .#hostname

# Or use --sudo flag
nixos-rebuild switch --flake .#hostname --sudo
```

## Helper Commands

```bash
ssh-test-keys       # Test SSH key configuration
ssh-copy-public-key # Copy public key to clipboard
```
