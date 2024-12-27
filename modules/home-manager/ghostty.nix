{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.ghostty;
in
{
  options.within.ghostty.enable = mkEnableOption "Enables ghostty Terminal Settings";

  config = mkIf cfg.enable {
    home.packages = [
      inputs.ghostty.packages."${pkgs.system}".default
    ];

    home.file = {
      ".config/ghostty/config" = {
        source = ../../dotfiles/ghostty/config;
      };
    };
  };
}
