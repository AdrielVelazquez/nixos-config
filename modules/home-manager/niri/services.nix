# modules/home-manager/niri/services.nix
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
  options.local.niri.services.enable = lib.mkEnableOption "Desktop services (polkit, cliphist, wlsunset, udiskie)";

  config = lib.mkIf (cfg.enable && cfg.services.enable) {
    # Polkit authentication agent
    systemd.user.services.hyprpolkitagent = {
      Unit = {
        Description = "Hyprland Polkit authentication agent";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.hyprpolkitagent}/libexec/hyprpolkitagent";
        Restart = "on-failure";
        RestartSec = 5;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # USB auto-mount with tray icon
    services.udiskie = {
      enable = true;
      tray = "auto";
    };

    # Clipboard history watcher
    systemd.user.services.cliphist = {
      Unit = {
        Description = "Clipboard history watcher";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store'";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Night light (color temperature shift)
    systemd.user.services.wlsunset = {
      Unit = {
        Description = "Day/night color temperature adjustment";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wlsunset}/bin/wlsunset -t 3500 -T 6500";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    home.packages = with pkgs; [
      swww
      grim
      slurp
      satty
      brightnessctl
      playerctl
      yazi
      oculante
      mpv
      cliphist
      wlsunset
      gpu-screen-recorder
      nwg-displays
      impala
      overskride
      pwvucontrol
      papirus-icon-theme
      libnotify
    ];
  };
}
