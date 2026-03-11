# CachyOS Framework 13 Setup

Fresh install guide for the Framework 13 laptop running CachyOS.

## 1. Install CachyOS

Download the ISO from https://cachyos.org and flash it to USB. During installation, pick your DE (COSMIC, KDE, etc.).

## 2. Install Nix

```bash
sh <(curl --proto '=https' --tlsv1.2 -L https://nixos.org/nix/install) --daemon
```

Restart your shell or open a new terminal after installation.

## 3. Clone this repo

```bash
git clone git@github.com:<your-org>/.nixos.git ~/.nixos
cd ~/.nixos
```

## 4. Bootstrap everything

This runs system-manager (system config) followed by home-manager (user config) in one command:

```bash
just bootstrap-cachyos
```

Or run them separately:

```bash
# System config only
just system-manager-switch cachyos-framework

# Home-manager only
nix --extra-experimental-features 'nix-command flakes' run .#homeConfigurations.reddit-framework13.activationPackage
```

## 5. Imperative setup

These steps can't be managed declaratively by system-manager and must be done manually once.

### Groups

```bash
sudo groupadd plugdev
sudo groupadd docker
sudo usermod -aG plugdev,docker,wheel adriel.velazquez
```

Log out and back in for group changes to take effect.

### Default shell

```bash
chsh -s $(which zsh)
```

## 6. Reboot

```bash
sudo reboot
```

## Updating after changes

After editing nix configs, re-apply with:

```bash
just system-manager-switch cachyos-framework
just home-activate-reddit
```
