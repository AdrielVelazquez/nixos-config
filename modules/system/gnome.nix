# modules/system/gnome.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.gnome;
in
{
  options.local.gnome.enable = lib.mkEnableOption "Enables GNOME desktop environment";

  config = lib.mkIf cfg.enable {
    services.xserver = {
      enable = true;
      displayManager.gdm.enable = true;
      desktopManager.gnome.enable = true;
      xkb = {
        layout = "us";
        variant = "";
      };
    };

    environment.gnome.excludePackages = with pkgs; [
      baobab
      epiphany
      geary
      gnome-backgrounds
      gnome-calendar
      gnome-connections
      gnome-console
      gnome-contacts
      gnome-font-viewer
      gnome-logs
      gnome-maps
      gnome-music
      gnome-software
      gnome-text-editor
      gnome-weather
      simple-scan
      snapshot
      totem
      yelp
    ];
  };
}
