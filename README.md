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
If you run into errors due to not pulling down a private repo you have to pass your ssh connections to root. 
```
sudo SSH_AUTH_SOCK=$SSH_AUTH_SOCK nixos-rebuild switch --upgrade --flake ~/.nixos#reddit-framework13 --show-trace

OR

nixos-rebuild switch --upgrade --flake ~/.nixos#reddit-framework13 --show-trace --sudo

```

# Running Nix on MacOS

```
darwin-rebuild switch --flake  ~/.nixos#PNH46YXX3Y --show-trace
```
# Build Home-manager for a specific user

```
home-manager switch --flake ./#adriel
```

# Running Non-Nixos Linux Systems

```
# System manager allows us to run openGL applications while still sandboxing the applications
sudo env "PATH=$PATH" nix run 'github:numtide/system-manager' -- switch --flake '.'
nix run .#homeConfigurations.reddit-framework13.activationPackage
```
