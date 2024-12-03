{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.zoom;
in
{
  options.within.zoom.enable = mkEnableOption "Enables Within's zoom config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.zoom-us
    ];
  };
}
