# Host entry point - kept minimal
# All customizations go in system-overrides.nix
{ ... }:

{
  imports = [
    # NOTE: You would add hardware-configuration.nix here after running:
    # nixos-generate-config --show-hardware-config > hardware-configuration.nix
    # ./hardware-configuration.nix
    ./system-overrides.nix
  ];

  # Basic host identity
  networking.hostName = "my-laptop";

  # IMPORTANT: Don't change this after initial install
  system.stateVersion = "24.05";
}

