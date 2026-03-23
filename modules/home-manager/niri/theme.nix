# modules/home-manager/niri/theme.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
in
{
  options.local.niri.theme.enable = lib.mkEnableOption "GTK dark theme, cursor, and dconf settings";

  config = lib.mkIf (cfg.enable && cfg.theme.enable) {
    gtk = {
      enable = true;
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
      gtk4.theme = config.gtk.theme;
      iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
      };
    };

    home.pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
      gtk.enable = true;
    };

    dconf.settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };
  };
}
