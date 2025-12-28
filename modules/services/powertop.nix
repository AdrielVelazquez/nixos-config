# modules/services/powertop.nix
{ lib, config, ... }:

let
  cfg = config.local.powertop;
in
{
  options.local.powertop.enable = lib.mkEnableOption "Enables PowerTOP auto-tune";

  config = lib.mkIf cfg.enable {
    powerManagement.powertop.enable = true;
  };
}
