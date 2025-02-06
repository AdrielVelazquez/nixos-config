{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.input-remapper;
in
{
  options.within.input-remapper.enable = mkEnableOption "Enables Within's input-remapper config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.input-remapper
    ];
  };
}
