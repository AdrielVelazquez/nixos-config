{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.gnome;
in
{
  options.within.gnome.enable = mkEnableOption "Enables gnome desktopManager";
  # gnome does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {

    # Enable the X11 windowing system.
    services.xserver.enable = true;

    # Enable the GNOME Desktop Environment.
    services.xserver.displayManager.gdm.enable = true;
    services.xserver.desktopManager.gnome.enable = true;

    # Configure keymap in X11
    services.xserver.xkb = {
      layout = "us";
      variant = "";
    };
    environment.gnome.excludePackages = with pkgs; [
      gnome-console
      geary
      # nixos-background-info
      gnome-backgrounds
      # gnome-bluetooth
      # gnome-color-manager
      # gnome-control-center
      # gnome-shell-extensions
      baobab
      epiphany
      gnome-text-editor
      gnome-calendar
      gnome-console
      gnome-contacts
      gnome-font-viewer
      gnome-logs
      gnome-maps
      gnome-music
      # gnome-system-monitor
      gnome-weather
      gnome-connections
      simple-scan
      snapshot
      totem
      yelp
      gnome-software
    ];
  };
}
