{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.discord;
in
{
  options.within.discord.enable = mkEnableOption "Enables Within's discord config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.discord
    ];
  };
}
