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
    # xdg.desktopEntries = {
    #   ghostty = {
    #     name = "Ghostty";
    #     genericName = "terminal";
    #     exec = "ghostty";
    #     mimeType = [
    #       "text/html"
    #       "text/xml"
    #     ];
    #     terminal = false;
    #     icon = "${config.home.homeDirectory}/.config/icons/ghostty.png";
    #   };
    # };
  };
}
