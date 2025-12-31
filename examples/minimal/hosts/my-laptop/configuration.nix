# Host entry point - kept minimal
# All customizations go in system-overrides.nix
{ ... }:

{
  imports = [
    # NOTE: In a real setup, you would add hardware-configuration.nix here after running:
    # nixos-generate-config --show-hardware-config > hardware-configuration.nix
    # ./hardware-configuration.nix
    ./system-overrides.nix
  ];

  # Basic host identity
  networking.hostName = "my-laptop";

  # Minimal hardware stubs for example to build
  # In a real config, these come from hardware-configuration.nix
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  boot.loader.systemd-boot.enable = true;

  # IMPORTANT: Don't change this after initial install
  system.stateVersion = "24.05";
}
