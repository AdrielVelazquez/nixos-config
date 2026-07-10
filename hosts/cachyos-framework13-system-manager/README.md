# CachyOS Framework 13

Setup and maintenance notes for the Framework 13 running CachyOS with the
flake outputs `systemConfigs.cachyos-framework` and
`homeConfigurations.cachyos-framework13`.

## Initial Setup

1. Install CachyOS from <https://cachyos.org/>.
2. Install Nix in multi-user mode.
3. Enter a temporary Nix shell that provides `git` and `just`.
4. Clone this repository using credentials that can read its private SSH flake
   inputs.
5. Review the configuration and run the bootstrap recipe.

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
nix shell nixpkgs#git nixpkgs#just
git clone git@github.com:AdrielVelazquez/nixos-config.git ~/.nixos
cd ~/.nixos
just bootstrap-cachyos
```

`just bootstrap-cachyos` is state-changing: it activates the system-manager
configuration as root and then activates Home Manager. The system-manager
invocation uses the `.#system-manager` app from this flake, so its executable is
the version pinned by `flake.lock` rather than a floating upstream version.

The two activation steps can also be run separately:

```bash
just system-manager-switch cachyos-framework
just home-activate-cachyos
```

Both commands change the active configuration. Use local validation first:

```bash
just check        # Evaluate current-system checks without building
just check-build  # Build current-system checks
```

## One-Time Host Steps

If the CachyOS Niri installation included Noctalia defaults that conflict with
the Nix-managed configuration, inspect the cleanup script before running it.
This is state-changing: it removes packages, orphaned dependencies, and local
Noctalia, Niri, and GTK configuration files.

```bash
./hosts/cachyos-framework13-system-manager/cleanup-noctalia.sh
```

Create any required host groups and set the login shell only after reviewing
the current users and group membership. These commands modify host accounts:

```bash
sudo groupadd -f plugdev
sudo groupadd -f docker
sudo groupadd -f input
sudo usermod -aG plugdev,docker,wheel,input "$USER"
chsh -s "$(command -v zsh)"
```

Log out and back in after changing group membership.

## RDSEED Microcode Diagnostic

`check-rdseed-microcode.sh` checks the running microcode, boot entries, and the
early microcode embedded in initramfs images:

```bash
./hosts/cachyos-framework13-system-manager/check-rdseed-microcode.sh
```

The default mode is diagnostic. The `--fix` mode is state-changing: it
reinstalls CachyOS kernels and triggers mkinitcpio and Limine hooks, thereby
modifying installed boot artifacts.

```bash
./hosts/cachyos-framework13-system-manager/check-rdseed-microcode.sh --fix
```

Review the script and ensure the system has a recoverable boot path before
using `--fix`.

## Hibernate Setup

`setup-hibernate.sh` discovers the root filesystem UUID and swapfile resume
offset at runtime. It creates or reuses disk-backed swap while leaving zram as
the preferred day-to-day swap.

Warning: this script modifies the swap configuration, appends to `/etc/fstab`,
writes boot parameters in `/etc/default/limine` or `/etc/kernel/cmdline`, and
runs `limine-update`. Review it before running as root.

```bash
./hosts/cachyos-framework13-system-manager/setup-hibernate.sh
./hosts/cachyos-framework13-system-manager/setup-hibernate.sh 80G
```

The optional argument sets the swapfile size. Environment variables
`SWAPFILE`, `SWAP_SIZE`, and `SWAP_PRIORITY` can override defaults. The script
requires an explicit interactive `yes` before changing the system. After
reviewing the detected values, automation may pass `--yes` to skip that prompt.

## Apple Studio Display

See [Framework 13 Apple Studio Display troubleshooting](../../docs/troubleshooting/framework13-apple-studio-display.md)
for link-rate and USB4 diagnostics, evidence behind the HBR3 workaround, and
its known limitations.
