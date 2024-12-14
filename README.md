# Starting from Scratch

Add the following line to /etc/nixos/configuration.nix

```
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

 Run `sudo nixos-rebuild switch` to install flakes

Copy your hardware-configuration.nix and any new changes to your configuration.nix into your git repo for your nix config.

!! Don't use your old hardware-configuration.nix as varibles have changed.

# Build Default Configuration

```
sudo nixos-rebuild switch --flake ~/.nixos#razer14
```
# Running Nix on MacOS

```
darwin-rebuild switch --flake  ~/.nixos#PNH46YXX3Y --show-trace
```
# Build Home-manager for a specific user

```
home-manager switch --flake ./#adriel
```
