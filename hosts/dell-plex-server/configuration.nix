# hosts/dell-plex-server/configuration.nix
# NixOS configuration for Dell Plex Server
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./custom-configuration.nix
    ../../modules/nixos/common.nix
  ];

  # Host-specific settings
  networking.hostName = "dell-plex";

  # LUKS encryption
  boot.initrd.luks.devices."luks-58932dcc-a18a-42f8-9898-945c17584abc".device =
    "/dev/disk/by-uuid/58932dcc-a18a-42f8-9898-945c17584abc";

  # Desktop Environment
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  # Keyboard layout
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # User account
  users.users.adriel = {
    isNormalUser = true;
    description = "Adriel Velazquez";
    extraGroups = [ "networkmanager" "wheel" ];
  };

  system.stateVersion = "24.05";
}
