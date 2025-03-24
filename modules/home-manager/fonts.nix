{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.fonts;
in
{
  options.within.fonts.enable = mkEnableOption "Enables Within's fonts config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.nerd-fonts.bigblue-terminal
      pkgs.nerd-fonts.victor-mono
      pkgs.nerd-fonts.zed-mono
      pkgs.nerd-fonts.mononoki
      pkgs.nerd-fonts.heavy-data
      pkgs.nerd-fonts.inconsolata
      pkgs.nerd-fonts.fira-code

    ];
  };
}
