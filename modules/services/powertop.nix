# modules/services/powertop.nix
{ lib, config, ... }:

let
  cfg = config.within.powertop;
in
{
  options.within.powertop.enable = lib.mkEnableOption "Enables PowerTOP auto-tune";

  config = lib.mkIf cfg.enable {
    powerManagement.powertop.enable = true;
  };
}
