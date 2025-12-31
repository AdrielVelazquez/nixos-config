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
├── parts/
│   ├── lib.nix               # Shared utilities
│   └── nixos.nix             # NixOS configuration
├── hosts/
│   └── my-laptop/
│       ├── configuration.nix
│       └── system-overrides.nix
├── modules/
│   └── system/
│       ├── default.nix       # Module imports
│       └── hello.nix         # Example module
└── users/
    └── myuser/
        └── default.nix       # Home Manager config
```

## Usage

```bash
# Build without switching (to test)
nixos-rebuild build --flake .#my-laptop

# Switch to the configuration
sudo nixos-rebuild switch --flake .#my-laptop
```

## Key Concepts Demonstrated

1. **Override Pattern**: `configuration.nix` is minimal; customizations go in `system-overrides.nix`
2. **Custom Modules**: `local.hello.enable` pattern for toggleable features
3. **Flake-parts**: Clean separation of concerns
4. **Home Manager**: User configuration integrated with NixOS

