# modules/home-manager/niri/fuzzel.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  fontFamily = cfg.style.font.family;
  rgba = color: alpha: "${lib.removePrefix "#" color}${alpha}";
in
{
  options.local.niri.fuzzel.enable = lib.mkEnableOption "Fuzzel application launcher";

  config = lib.mkIf (cfg.enable && cfg.fuzzel.enable) {
    home.packages = [ pkgs.fuzzel ];

    xdg.configFile."fuzzel/fuzzel.ini".text = ''
      [main]
      font=${fontFamily}:size=14
      terminal=${lib.getExe pkgs.kitty}
      prompt=Run:
      icons-enabled=yes
      show-actions=yes
      fields=name,generic,comment,categories,filename,keywords
      lines=12
      width=48
      horizontal-pad=16
      vertical-pad=12
      inner-pad=8

      [colors]
      background=${rgba palette.background "e6"}
      text=${rgba palette.foreground "ff"}
      match=${rgba palette.accent "ff"}
      selection=${rgba palette.inactive "ff"}
      selection-text=${rgba palette.foreground "ff"}
      selection-match=${rgba palette.accent "ff"}
      border=${rgba palette.accent "ff"}

      [border]
      width=2
      radius=8
    '';
  };
}
