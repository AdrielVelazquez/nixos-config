{ lib, config, ... }:

with lib;

let
  cfg = config.within.powertop;
in
{
  options.within.powertop.enable = mkEnableOption "Enables powertop Settings";

  config = mkIf cfg.enable {
    powerManagement.powertop.enable = true;
  };
}
