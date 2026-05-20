# modules/home-manager/niri/wallpaper.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  swaybg = lib.getExe pkgs.swaybg;
in
{
  options.local.niri = {
    wallpaperService.enable = lib.mkEnableOption "static wallpaper daemon";
    awww.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Deprecated compatibility alias for local.niri.wallpaperService.enable.";
    };
    swww.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Deprecated compatibility alias for local.niri.wallpaperService.enable.";
    };
  };

  config = lib.mkIf (cfg.enable && (cfg.wallpaperService.enable || cfg.awww.enable || cfg.swww.enable)) {
    warnings =
      lib.optional cfg.awww.enable ''
        local.niri.awww.enable is deprecated. Use local.niri.wallpaperService.enable instead.
      ''
      ++ lib.optional cfg.swww.enable ''
        local.niri.swww.enable is deprecated. Use local.niri.wallpaperService.enable instead.
      '';

    systemd.user.services.swaybg = {
      Unit = {
        Description = "Static Wayland wallpaper";
        Conflicts = [
          "awww.service"
          "swww.service"
        ];
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${swaybg} --image ${lib.escapeShellArg (toString cfg.wallpaper)} --mode fill";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
