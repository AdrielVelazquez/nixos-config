# modules/services/mullvad.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.within.mullvad;
in
{
  options.within.mullvad.enable = lib.mkEnableOption "Enables Mullvad VPN";

  config = lib.mkIf cfg.enable {
    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };
  };
}
