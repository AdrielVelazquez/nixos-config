# Minimal NixOS Flake Example

This directory is a small reference for the same direct-output layout used by
the main repository. It contains one NixOS host, one custom module, and one
Home Manager user integrated into the NixOS activation boundary.

## Structure

```text
minimal/
├── flake.nix
├── flake.lock
├── justfile
├── hosts/
│   └── my-laptop/
│       ├── configuration.nix
│       └── system-overrides.nix
├── modules/
│   └── system/
│       ├── default.nix
│       └── hello.nix
└── users/
    └── myuser/
        └── default.nix
```

`flake.nix` exports `nixosConfigurations.my-laptop` directly. The host entry
point owns machine identity and hardware imports, `modules/system/` contains
reusable behavior, and `users/myuser/` contains Home Manager configuration.
There is no separate flake assembly directory.

## Starting From A Fresh NixOS Installation

Boot the NixOS installer, connect to the network, and enter a temporary shell:

```bash
nix-shell -p git just
```

Clone your copy of the configuration and enter the example directory:

```bash
git clone https://github.com/yourusername/nixos-config ~/.nixos
cd ~/.nixos/examples/minimal
```

Copy the generated hardware configuration into the host directory:

```bash
cp /etc/nixos/hardware-configuration.nix hosts/my-laptop/
```

Then enable it in `hosts/my-laptop/configuration.nix`:

```nix
imports = [
  ./hardware-configuration.nix
  ./system-overrides.nix
];
```

Replace the placeholder root filesystem settings in `configuration.nix` with
the generated hardware configuration as appropriate for the machine. Update
the `myuser` username, home directory, and user account before activation.

## Validate Before Activation

Evaluate the exact NixOS output without changing the running system:

```bash
nix eval .#nixosConfigurations.my-laptop.config.system.build.toplevel.drvPath
```

For a fuller build preview:

```bash
just bootstrap-dry my-laptop
```

After reviewing the result, the initial state-changing installation is:

```bash
just bootstrap my-laptop
```

The bootstrap recipe temporarily enables `nix-command` and flakes and runs
`nixos-rebuild switch` through `nixpkgs`. Subsequent rebuilds can use
`just switch my-laptop`.

## Configuration Boundaries

- `flake.nix` declares inputs and exported configurations.
- `hosts/my-laptop/configuration.nix` is the machine entry point.
- `hosts/my-laptop/system-overrides.nix` holds machine-specific choices.
- `modules/system/hello.nix` demonstrates an opt-in `local.*` module.
- `users/myuser/default.nix` configures the user through Home Manager.

Run `just --list` for the available validation, build, activation, formatting,
and maintenance recipes.
