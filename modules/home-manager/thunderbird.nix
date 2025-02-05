{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.thunderbird;
in
{
  options.within.thunderbird.enable = mkEnableOption "Enables Within's thunderbird config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.thunderbird
    ];
  };
}
