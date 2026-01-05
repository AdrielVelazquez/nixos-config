# modules/profiles/server.nix
{ lib, ... }:

{
  imports = [
    ./base.nix
  ];

  services.logind.lidSwitch = lib.mkDefault "ignore";
  services.logind.lidSwitchExternalPower = lib.mkDefault "ignore";
  hardware.bluetooth.enable = lib.mkDefault false;
  services.printing.enable = lib.mkDefault false;

  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
    };
  };
}
