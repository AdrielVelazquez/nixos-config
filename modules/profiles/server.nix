# modules/profiles/server.nix
# Server systems - minimal, headless, no desktop
{ lib, ... }:

{
  imports = [
    ./base.nix
  ];

  # ============================================================================
  # Server-specific Settings
  # ============================================================================
  # Disable suspend on servers
  services.logind.lidSwitch = lib.mkDefault "ignore";
  services.logind.lidSwitchExternalPower = lib.mkDefault "ignore";

  # No bluetooth on servers by default
  hardware.bluetooth.enable = lib.mkDefault false;

  # No printing on servers
  services.printing.enable = lib.mkDefault false;

  # ============================================================================
  # SSH (servers should have SSH enabled)
  # ============================================================================
  services.openssh = {
    enable = lib.mkDefault true;
    settings = {
      PermitRootLogin = lib.mkDefault "no";
      PasswordAuthentication = lib.mkDefault false;
    };
  };
}
