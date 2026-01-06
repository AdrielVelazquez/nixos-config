# Minimal NixOS Flake Example

A minimal example demonstrating the configuration structure with:

- 1 NixOS host
- 1 custom module
- 1 user (via Home Manager)
- Flake-parts for organization

## Structure

```
minimal/
├── flake.nix                 # Entry point
├── justfile                  # Command runner for easy bootstrapping
├── parts/
│   ├── lib.nix               # Shared utilities
│   └── nixos.nix             # NixOS configuration
├── hosts/
│   └── my-laptop/
│       ├── configuration.nix         # From /etc/nixos/configuration.nix
│       ├── hardware-configuration.nix # From /etc/nixos/hardware-configuration.nix
│       ├── hardware-overrides.nix     # Your hardware tweaks
│       └── system-overrides.nix       # Your system customizations
├── modules/
│   └── system/
│       ├── default.nix       # Module imports
│       └── hello.nix         # Example module
└── users/
    └── myuser/
        └── default.nix       # Home Manager config
```

---

## Getting Started from Scratch

This guide walks you through setting up NixOS from a fresh installation using this minimal configuration.

### Prerequisites

- Network connection (WiFi or Ethernet)

---

### Step 1: Boot into NixOS and Connect to Network

After booting into the NixOS, connect to WiFi if needed:

```bash
# List available WiFi networks
nmcli device wifi list

# Connect to your network
nmcli device wifi connect "YourNetworkName" password "YourPassword"

# Verify connectivity
ping -c 3 google.com
```

Or just use whatever DE you're using

---

### Step 2: Enter a Shell with Git and Just

```bash
nix-shell -p git just
```

This gives you access to `git` and `just` without permanently installing them.

---

### Step 3: Clone This Configuration

```bash
git clone https://github.com/yourusername/nixos-config ~/.nixos
cd ~/.nixos
```

---

### Step 4: Copy Your Generated Configuration

Both `configuration.nix` and `hardware-configuration.nix` are generated from your NixOS installation at `/etc/nixos/`. Copy them into the host directory:

```bash
cp /etc/nixos/hardware-configuration.nix hosts/my-laptop/
cp /etc/nixos/configuration.nix hosts/my-laptop/
```

Then update `hosts/my-laptop/configuration.nix` to import the override files (hardware-configuration.nix is already imported by default):

```nix
{ ... }:

{
  imports = [
    ./hardware-configuration.nix  # Already there from generated config
    ./hardware-overrides.nix      # Add this - hardware tweaks
    ./system-overrides.nix        # Add this - system customizations
  ];

  # ... rest of your generated config
}
```

---

### Step 5: Bootstrap with Just

The `justfile` includes commands that automatically enable flakes without requiring any system configuration changes:

```bash
# See available commands
just --list

# Bootstrap NixOS (first-time install)
just bootstrap my-laptop

# Or dry-run first to see what would be built
just bootstrap-dry my-laptop
```

**What the bootstrap command does:**
```bash
sudo nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-rebuild -- switch --flake .#my-laptop
```

This:
1. Temporarily enables `nix-command` and `flakes` experimental features
2. Runs `nixos-rebuild` from nixpkgs (no need to have it installed)
3. Switches to the new configuration

---

### Step 6: Reboot

```bash
sudo reboot
```

After reboot, your system will be running the new configuration!

---

## Subsequent Rebuilds

Once bootstrapped, flakes are enabled in your configuration. You can use simpler commands:

```bash
cd ~/.nixos

# Rebuild and switch
just switch my-laptop

# Or without just:
sudo nixos-rebuild switch --flake .#my-laptop
```

---

## The Justfile

Create this `justfile` in your configuration root:

```just
# justfile - NixOS configuration commands

# Show available commands
default:
    @just --list

# ============================================================================
# Bootstrap (Fresh Install - no flakes enabled yet)
# ============================================================================

# Bootstrap NixOS from fresh install (enables flakes automatically)
bootstrap hostname:
    sudo nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-rebuild -- switch --flake .#{{hostname}}

# Dry-run bootstrap to preview changes
bootstrap-dry hostname:
    nix --extra-experimental-features 'nix-command flakes' run nixpkgs#nixos-rebuild -- dry-build --flake .#{{hostname}}

# ============================================================================
# Normal Usage (after bootstrap, flakes are enabled)
# ============================================================================

# Rebuild and switch to new configuration
switch hostname:
    sudo nixos-rebuild switch --flake .#{{hostname}}

# Build without switching (to test)
build hostname:
    nixos-rebuild build --flake .#{{hostname}}

# Test configuration (reverts on reboot)
test hostname:
    sudo nixos-rebuild test --flake .#{{hostname}}

# ============================================================================
# Maintenance
# ============================================================================

# Update all flake inputs
update:
    nix flake update

# Garbage collect old generations
gc:
    sudo nix-collect-garbage -d

# Format all Nix files
fmt:
    find . -name "*.nix" | xargs nixfmt
```

---

## Key Concepts Demonstrated

1. **Override Pattern**: `configuration.nix` is minimal; customizations go in `system-overrides.nix`
2. **Custom Modules**: `local.hello.enable` pattern for toggleable features
3. **Flake-parts**: Clean separation of concerns
4. **Home Manager**: User configuration integrated with NixOS
5. **Bootstrap Pattern**: First-time setup without pre-configuring flakes

---

## Quick Reference

| Task | Command |
|------|---------|
| First-time install | `just bootstrap my-laptop` |
| Preview first install | `just bootstrap-dry my-laptop` |
| Normal rebuild | `just switch my-laptop` |
| Update dependencies | `just update` |
| Clean old generations | `just gc` |

---

## Troubleshooting

### "experimental feature 'flakes' is disabled"

Use the bootstrap command which includes the experimental flags:
```bash
just bootstrap my-laptop
```

### "cannot find flake.nix"

Make sure you're in the configuration directory:
```bash
cd ~/.nixos  # or wherever you cloned the config
```

### Configuration files missing

Copy them from your existing NixOS installation:
```bash
cp /etc/nixos/hardware-configuration.nix hosts/my-laptop/
cp /etc/nixos/configuration.nix hosts/my-laptop/
```
