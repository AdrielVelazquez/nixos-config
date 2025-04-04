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
    # fonts.fontconfig.enable = true;
    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [
          "Maple Mono NF"
          "Maple Mono NF"
        ];
        sansSerif = [
          "Maple Mono NF"
          "Maple Mono NF"
        ];
        monospace = [ "Maple Mono NF" ];
      };
    };
    home.packages = [
      pkgs.nerd-fonts.caskaydia-cove
      pkgs.nerd-fonts.bigblue-terminal
      pkgs.nerd-fonts.victor-mono
      pkgs.nerd-fonts.zed-mono
      pkgs.nerd-fonts.mononoki
      pkgs.nerd-fonts.heavy-data
      pkgs.nerd-fonts.inconsolata
      pkgs.nerd-fonts.fira-code
      pkgs.nerd-fonts.symbols-only
      # Maple Mono (Ligature TTF unhinted)
      pkgs.maple-mono.truetype
      # Maple Mono NF (Ligature unhinted)
      pkgs.maple-mono.NF-unhinted
    ];
  };
}
