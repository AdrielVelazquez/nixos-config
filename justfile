# ~/.nixos/justfile
# Common commands for managing NixOS configuration
# Run `just --list` to see all available commands

# Block sleep/suspend/idle while long-running rebuild & maintenance tasks run.
# Prefix any recipe body that does a rebuild, GC, update, or activation with
# `{{inhibit}}` so closing the lid mid-`just switch` doesn't kill the build.
inhibit := 'systemd-inhibit --why="Running just task for nixos" --who=just --mode=block'

# Default recipe - show help
default:
    @just --list

# ============================================================================
# Formatting & Linting
# ============================================================================

# Format Nix and Lua files (keeps nixfmt fast; runs stylua from nixpkgs)
fmt:
    find . -name "*.nix" -not -path "./result/*" -print0 | xargs -0 nixfmt
    find . -name "*.lua" -not -path "./result/*" -print0 | xargs -0 nix run nixpkgs#stylua --

# Evaluate all current-system flake checks without building them
check:
    nix flake check --no-build

# Build all current-system flake checks
check-build:
    {{inhibit}} nix flake check --print-build-logs

# Show flake info
info:
    nix flake show

# ============================================================================
# Bootstrap (Fresh Install)
# ============================================================================

# Bootstrap NixOS from a fresh install (enables flakes automatically)
# Usage: just bootstrap razer14
# Available hosts: razer14, dell-plex
bootstrap hostname:
    {{inhibit}} sudo nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-rebuild -- switch --flake .#{{hostname}}

# Bootstrap and show what would be built (dry-run)
bootstrap-dry hostname:
    {{inhibit}} nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-rebuild -- dry-build --flake .#{{hostname}}

# Bootstrap Home Manager on non-NixOS systems (e.g., CachyOS, Ubuntu)
# Usage: just bootstrap-home cachyos-framework13
bootstrap-home config:
    {{inhibit}} nix --extra-experimental-features 'nix-command flakes' run .#homeConfigurations.{{config}}.activationPackage

# List available NixOS hosts
list-hosts:
    @echo "Available NixOS hosts:"
    @nix --extra-experimental-features 'nix-command flakes' flake show --json 2>/dev/null | jq -r '.nixosConfigurations | keys[]' 2>/dev/null || echo "  razer14, dell-plex"

# List available Home Manager configs
list-homes:
    @echo "Available Home Manager configurations:"
    @nix --extra-experimental-features 'nix-command flakes' flake show --json 2>/dev/null | jq -r '.homeConfigurations | keys[]' 2>/dev/null || echo "  razer14, cachyos-framework13"

# ============================================================================
# NixOS System Commands
# ============================================================================

# Note: no `--show-trace` in the hot path -- it measurably slows eval and
# balloons daemon memory. Use `just switch-trace <host>` when a build is
# actually failing and you need the full trace.

# Rebuild and switch to new NixOS configuration (hosts: razer14, dell-plex)
switch hostname:
    {{inhibit}} sudo nixos-rebuild switch --flake .#{{hostname}}

# Same as `just switch` but with `--show-trace` for debugging eval errors.
switch-trace hostname:
    {{inhibit}} sudo nixos-rebuild switch --flake .#{{hostname}} --show-trace

# Build NixOS configuration without switching
# See `just switch` for available hosts
build hostname:
    {{inhibit}} nixos-rebuild build --flake .#{{hostname}}

# Test NixOS configuration (switch temporarily, reverts on reboot)
# See `just switch` for available hosts
test hostname:
    {{inhibit}} sudo nixos-rebuild test --flake .#{{hostname}}

# Dry-run build to see what would change
# See `just switch` for available hosts
dry-run hostname:
    {{inhibit}} nixos-rebuild dry-build --flake .#{{hostname}}

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

# Note: no `{{inhibit}}` here — systemd-inhibit is Linux-only.
# Use `caffeinate -dimsu just darwin-switch ...` on macOS if needed.
# Rebuild and switch Darwin configuration
darwin-switch hostname:
    sudo darwin-rebuild switch --flake .#{{hostname}}

# Build Darwin configuration without switching
darwin-build hostname:
    darwin-rebuild build --flake .#{{hostname}}

# ============================================================================
# Home Manager Commands
# ============================================================================

# Note: no `{{inhibit}}` here because `home-switch` is also invoked on macOS
# where systemd-inhibit doesn't exist. Use `home-activate-cachyos` on Linux
# if you want the inhibit wrapper.
# Switch Home Manager configuration (requires home-manager installed)
home-switch config:
    home-manager switch --flake .#{{config}}

# Build Home Manager configuration (requires home-manager installed)
home-build config:
    home-manager build --flake .#{{config}}

# Activate Home Manager via nix run (for non-NixOS systems without home-manager CLI)
home-activate config:
    {{inhibit}} nix run .#homeConfigurations.{{config}}.activationPackage

# Activate cachyos-framework13 home config (convenience alias)
home-activate-cachyos:
    {{inhibit}} nix --extra-experimental-features 'nix-command flakes' run .#homeConfigurations.cachyos-framework13.activationPackage --show-trace

# ============================================================================
# System Manager Commands (Non-NixOS Linux)
# ============================================================================

# Install native PAM/D-Bus prerequisites for Framework (explicit host mutation)
bootstrap-cachyos-prereqs:
    sudo /usr/bin/pacman -S --needed greetd greetd-tuigreet hyprlock bolt
    sudo /usr/bin/systemctl disable --now sddm.service || true
    sudo /usr/bin/systemctl set-default graphical.target

# Remove the native Fleet package before the first Nix-managed Orbit activation.
migrate-cachyos-orbit:
    #!/usr/bin/env bash
    set -euo pipefail

    package=fleet-osquery
    if ! /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
        echo "Native Fleet package '$package' is already absent; no migration is needed."
        exit 0
    fi

    sudo /usr/bin/systemctl stop orbit.service 2>/dev/null || true
    sudo /usr/bin/pacman -R "$package"
    sudo /usr/bin/systemctl daemon-reload

# Activate system-manager configuration
# Available config: cachyos-framework13
system-manager-switch config:
    {{inhibit}} sudo /nix/var/nix/profiles/default/bin/nix --extra-experimental-features 'nix-command flakes' run '.#system-manager' -- switch --flake '.#{{config}}' --nix-option show-trace true

# Bootstrap CachyOS Framework 13 from scratch (system-manager + home-manager)
bootstrap-cachyos: bootstrap-cachyos-prereqs
    {{inhibit}} sudo /nix/var/nix/profiles/default/bin/nix --extra-experimental-features 'nix-command flakes' run '.#system-manager' -- switch --flake '.#cachyos-framework13' --nix-option show-trace true
    {{inhibit}} nix --extra-experimental-features 'nix-command flakes' run .#homeConfigurations.cachyos-framework13.activationPackage

# ============================================================================
# Maintenance
# ============================================================================

# Update all flake inputs
update:
    {{inhibit}} nix flake update

# Update a specific input
update-input input:
    {{inhibit}} nix flake update {{input}}

# Garbage collect old generations (both user and system profiles)
gc:
    {{inhibit}} nix-collect-garbage -d
    {{inhibit}} sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage -d

# Garbage collect generations older than N days (both user and system)
gc-older days="7":
    {{inhibit}} nix-collect-garbage --delete-older-than {{days}}d
    {{inhibit}} sudo /nix/var/nix/profiles/default/bin/nix-collect-garbage --delete-older-than {{days}}d

# Optimize nix store (deduplicates identical files)
optimize:
    {{inhibit}} sudo /nix/var/nix/profiles/default/bin/nix-store --optimise

# Full cleanup: gc + optimize
clean: gc optimize

# List all system generations
generations:
    sudo nix-env --list-generations --profile /nix/var/nix/profiles/system

# ============================================================================
# Diff & Debug
# ============================================================================

# Show diff between current and new configuration
diff hostname:
    {{inhibit}} nixos-rebuild build --flake .#{{hostname}} && nvd diff /run/current-system result

# Show flake inputs
inputs:
    nix flake metadata --json | jq '.locks.nodes | keys[]' -r

# Evaluate a specific attribute (for debugging)
eval attr:
    nix eval .#{{attr}}

# REPL with flake loaded
repl:
    nix repl .
