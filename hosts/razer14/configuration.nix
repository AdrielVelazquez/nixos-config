# hosts/razer14/configuration.nix
# NixOS configuration for Razer Blade 14
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-overrides.nix
    ./system-overrides.nix
    ../../modules/nixos/common.nix
  ];

  # Host-specific settings
  networking.hostName = "razer14";

  # LUKS encryption
  boot.initrd.luks.devices."luks-cd21de89-443f-44ff-afb5-18fd412dc80c".device =
    "/dev/disk/by-uuid/cd21de89-443f-44ff-afb5-18fd412dc80c";

  # Keyboard layout
  services.xserver.xkb = {
    layout = "us";
    variant = "colemak_dh_ortho";
  };

  # User account
  users.users.adriel = {
    isNormalUser = true;
    description = "Adriel Velazquez";
    extraGroups = [
      "networkmanager"
      "wheel"
      "openrazer"
    ];
  };

  system.stateVersion = "25.11";
}
