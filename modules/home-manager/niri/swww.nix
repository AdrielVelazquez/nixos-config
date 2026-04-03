# modules/home-manager/niri/swww.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  awww = lib.getExe pkgs.awww;
  awwwDaemon = lib.getExe' pkgs.awww "awww-daemon";
in
{
  options.local.niri.swww.enable = lib.mkEnableOption "swww wallpaper daemon";

  config = lib.mkIf (cfg.enable && cfg.swww.enable) {
    systemd.user.services.swww = {
      Unit = {
        Description = "swww wallpaper daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = awwwDaemon;
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.swww-wallpaper = {
      Unit = {
        Description = "Set wallpaper via swww";
        After = [ "swww.service" ];
        Requires = [ "swww.service" ];
        PartOf = [ "swww.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${awww} img ${cfg.wallpaper}";
      };
      Install.WantedBy = [ "swww.service" ];
    };
  };
}
