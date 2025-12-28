# modules/home-manager/fonts.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.fonts;
in
{
  options.local.fonts.enable = lib.mkEnableOption "Enables font configuration";

  config = lib.mkIf cfg.enable {
    fonts.fontconfig = {
      enable = true;
      defaultFonts = {
        serif = [ "Maple Mono NF" ];
        sansSerif = [ "Maple Mono NF" ];
        monospace = [ "Maple Mono NF" ];
      };
    };

    home.packages = with pkgs; [
      nerd-fonts.caskaydia-cove
      nerd-fonts.bigblue-terminal
      nerd-fonts.victor-mono
      nerd-fonts.zed-mono
      nerd-fonts.mononoki
      nerd-fonts.heavy-data
      nerd-fonts.inconsolata
      nerd-fonts.fira-code
      nerd-fonts.symbols-only
      maple-mono.truetype
      maple-mono.NF-unhinted
    ];
  };
}
