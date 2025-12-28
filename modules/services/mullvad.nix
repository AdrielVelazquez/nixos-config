# modules/services/mullvad.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.mullvad;
in
{
  options.local.mullvad.enable = lib.mkEnableOption "Enables Mullvad VPN";

  config = lib.mkIf cfg.enable {
    services.mullvad-vpn = {
      enable = true;
      package = pkgs.mullvad-vpn;
    };
  };
}
