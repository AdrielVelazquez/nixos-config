# ~/.nixos/justfile
# Common commands for managing NixOS configuration
# Run `just --list` to see all available commands

# Default recipe - show help
default:
    @just --list

# ============================================================================
# Formatting & Linting
# ============================================================================

# Format all Nix files (uses nixfmt directly to avoid slow flake evaluation)
fmt:
    find . -name "*.nix" -not -path "./result/*" | xargs nixfmt

# Check flake for errors without building
check:
    nix flake check

# Show flake info
info:
    nix flake show

# ============================================================================
# NixOS System Commands
# ============================================================================

# Rebuild and switch to new NixOS configuration
# Available hosts:
#   just switch razer14  - Razer Blade 14 laptop
#   just switch dell     - Dell Plex server
switch hostname="":
    #!/usr/bin/env bash
    if [ -z "{{hostname}}" ]; then
        sudo nixos-rebuild switch --flake .
    else
        sudo nixos-rebuild switch --flake .#{{hostname}}
    fi

# Build NixOS configuration without switching
# See `just switch` for available hosts
build hostname="":
    #!/usr/bin/env bash
    if [ -z "{{hostname}}" ]; then
        nixos-rebuild build --flake .
    else
        nixos-rebuild build --flake .#{{hostname}}
    fi

# Test NixOS configuration (switch temporarily, reverts on reboot)
# See `just switch` for available hosts
test hostname="":
    #!/usr/bin/env bash
    if [ -z "{{hostname}}" ]; then
        sudo nixos-rebuild test --flake .
    else
        sudo nixos-rebuild test --flake .#{{hostname}}
    fi

# Dry-run build to see what would change
# See `just switch` for available hosts
dry-run hostname="":
    #!/usr/bin/env bash
    if [ -z "{{hostname}}" ]; then
        nixos-rebuild dry-build --flake .
    else
        nixos-rebuild dry-build --flake .#{{hostname}}
    fi

# Rollback to previous NixOS generation (no internet required)
rollback:
    sudo nixos-rebuild switch --rollback

# Switch to a specific generation number
switch-generation gen:
    sudo nix-env --switch-generation {{gen}} --profile /nix/var/nix/profiles/system
    sudo /nix/var/nix/profiles/system/bin/switch-to-configuration switch

# ============================================================================
# Darwin (macOS) Commands
# ============================================================================

# Rebuild and switch Darwin configuration
darwin-switch hostname="PNH46YXX3Y":
    sudo darwin-rebuild switch --flake .#{{hostname}}

# Build Darwin configuration without switching
darwin-build hostname="PNH46YXX3Y":
    darwin-rebuild build --flake .#{{hostname}}

# ============================================================================
# Home Manager Commands
# ============================================================================

# Switch Home Manager configuration (requires home-manager installed)
home-switch config="":
    #!/usr/bin/env bash
    if [ -z "{{config}}" ]; then
        home-manager switch --flake .
    else
        home-manager switch --flake .#{{config}}
    fi

# Build Home Manager configuration (requires home-manager installed)
home-build config="":
    #!/usr/bin/env bash
    if [ -z "{{config}}" ]; then
        home-manager build --flake .
    else
        home-manager build --flake .#{{config}}
    fi

# Activate Home Manager via nix run (for non-NixOS systems without home-manager CLI)
home-activate config:
    nix run .#homeConfigurations.{{config}}.activationPackage

# Activate reddit-framework13 home config (convenience alias)
home-activate-reddit:
    nix run .#homeConfigurations.reddit-framework13.activationPackage

# ============================================================================
# System Manager Commands (Non-NixOS Linux)
# ============================================================================

# Activate system-manager configuration
system-manager-switch:
    sudo env "PATH=$PATH" nix run 'github:numtide/system-manager' -- switch --flake '.' --nix-option show-trace true

# Rollback mediatek-wifi changes (removes config files)
system-manager-rollback-mediatek:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Removing config files..."
    sudo rm -f /etc/modprobe.d/mediatek-wifi.conf
    sudo rm -f /etc/NetworkManager/conf.d/99-mediatek-wifi.conf
    echo "Restarting NetworkManager..."
    sudo systemctl restart NetworkManager
    echo "Rollback complete. Kernel module params persist until reboot."

# ============================================================================
# Maintenance
# ============================================================================

# Update all flake inputs
update:
    nix flake update

# Update a specific input
update-input input:
    nix flake lock --update-input {{input}}

# Garbage collect old generations (both user and system profiles)
gc:
    nix-collect-garbage -d
    sudo env "PATH=$PATH" nix-collect-garbage -d

# Garbage collect generations older than N days (both user and system)
gc-older days="7":
    nix-collect-garbage --delete-older-than {{days}}d
    sudo env "PATH=$PATH" nix-collect-garbage --delete-older-than {{days}}d

# Optimize nix store (deduplicates identical files)
optimize:
    sudo env "PATH=$PATH" nix-store --optimise

# Full cleanup: gc + optimize
clean: gc optimize

# List all system generations
generations:
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# ============================================================================
# Development
# ============================================================================

# Enter Python dev shell
dev-python:
    nix develop .#python

# Enter default dev shell
dev:
    nix develop

# ============================================================================
# Diff & Debug
# ============================================================================

# Show diff between current and new configuration
diff hostname="":
    #!/usr/bin/env bash
    if [ -z "{{hostname}}" ]; then
        nixos-rebuild build --flake . && nvd diff /run/current-system result
    else
        nixos-rebuild build --flake .#{{hostname}} && nvd diff /run/current-system result
    fi

# Show flake inputs
inputs:
    nix flake metadata --json | jq '.locks.nodes | keys[]' -r

# Evaluate a specific attribute (for debugging)
eval attr:
    nix eval .#{{attr}}

# REPL with flake loaded
repl:
    nix repl .

