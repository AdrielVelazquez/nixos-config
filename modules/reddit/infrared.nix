
{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.infrared;
in
{
  options.within.infrared.enable = mkEnableOption "Enables Within's infrared config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.infrared
    ];
  };
}
