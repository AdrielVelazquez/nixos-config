# modules/home-manager/niri/mako.nix
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
  makoBin = lib.getExe pkgs.mako;
  makoCtlBin = lib.getExe' pkgs.mako "makoctl";
  iconPath = lib.concatStringsSep ":" [
    "${pkgs.papirus-icon-theme}/share/icons/Papirus"
    "${pkgs.adwaita-icon-theme}/share/icons/Adwaita"
    "${pkgs.hicolor-icon-theme}/share/icons/hicolor"
  ];
in
{
  options.local.niri.mako.enable = lib.mkEnableOption "Mako notification daemon";

  config = lib.mkIf (cfg.enable && cfg.mako.enable) {
    services.mako = {
      enable = true;
      package = pkgs.mako;
      settings = {
        anchor = "top-right";
        layer = "top";
        sort = "-time";
        width = 400;
        height = 160;
        margin = 8;
        padding = "10,12";
        "outer-margin" = "54,18,0,0";
        "border-size" = 2;
        "border-radius" = 10;
        "background-color" = "${palette.background}e6";
        "text-color" = "${palette.foreground}ff";
        "border-color" = "${palette.inactive}ff";
        "progress-color" = "over ${palette.accent}ff";
        font = "${fontFamily} 11";
        icons = 1;
        "max-icon-size" = 40;
        "icon-path" = iconPath;
        actions = 1;
        markup = 1;
        "default-timeout" = 5000;
        "ignore-timeout" = 1;
        history = 1;
        "max-history" = 5;
        "max-visible" = 3;
        "group-by" = "app-name,summary";

        "urgency=critical" = {
          "border-color" = "${palette.danger}ff";
          "default-timeout" = 0;
        };

        "mode=do-not-disturb" = {
          invisible = 1;
        };
      };
    };

    systemd.user.services.mako = {
      Unit = {
        Description = "Lightweight Wayland notification daemon";
        Documentation = [ "man:mako(1)" ];
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
        ConditionEnvironment = "WAYLAND_DISPLAY";
      };

      Service = {
        Type = "dbus";
        BusName = "org.freedesktop.Notifications";
        ExecStart = makoBin;
        ExecReload = "${makoCtlBin} reload";
        ExecStartPost = "${makoCtlBin} mode -a do-not-disturb";
        Restart = "on-failure";
      };

      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
