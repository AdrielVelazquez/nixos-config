# hosts/razer14/configuration.nix
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-overrides.nix
    ./system-overrides.nix
  ];

  networking.hostName = "razer14";

  boot.initrd.luks.devices."luks-cd21de89-443f-44ff-afb5-18fd412dc80c".device =
    "/dev/disk/by-uuid/cd21de89-443f-44ff-afb5-18fd412dc80c";

  services.xserver.xkb = {
    layout = "us";
    variant = "colemak_dh_ortho";
  };

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
