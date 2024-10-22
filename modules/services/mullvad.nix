
{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.mullvad;
in {
  options.within.mullvad.enable = mkEnableOption "Enables mullvad Settings";

  config = mkIf cfg.enable {
    services.mullvad-vpn.enable = true;
    services.mullvad-vpn.package = pkgs.mullvad-vpn;
  };
}

