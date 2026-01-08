# hosts/razer14/configuration.nix
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
    ./hardware-overrides.nix
    ./system-overrides.nix
  ];

  networking.hostName = "razer14";

  boot.initrd.luks.devices."luks-02e42960-4936-4e3f-8af3-77e80135dd9f".device = "/dev/disk/by-uuid/02e42960-4936-4e3f-8af3-77e80135dd9f";

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
