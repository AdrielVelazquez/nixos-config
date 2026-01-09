# hosts/razer14/configuration.nix
{ pkgs, inputs, ... }:

{
  imports = [
    inputs.disko.nixosModules.disko
    ./disko.nix
    ./hardware.nix
    ./system-overrides.nix
  ];

  networking.hostName = "razer14";

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
