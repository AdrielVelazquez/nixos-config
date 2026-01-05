# hosts/dell-plex-server/configuration.nix
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./system-overrides.nix
  ];

  networking.hostName = "dell-plex";

  boot.initrd.luks.devices."luks-58932dcc-a18a-42f8-9898-945c17584abc".device =
    "/dev/disk/by-uuid/58932dcc-a18a-42f8-9898-945c17584abc";

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  users.users.adriel = {
    isNormalUser = true;
    description = "Adriel Velazquez";
    extraGroups = [
      "networkmanager"
      "wheel"
    ];
  };

  system.stateVersion = "24.05";
}
