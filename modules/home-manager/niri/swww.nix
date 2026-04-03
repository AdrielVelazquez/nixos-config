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
  cacheDir = "${config.home.homeDirectory}/.cache/awww";
  wallpaperSetter = pkgs.writeShellScript "awww-set-wallpaper" ''
    set -eu

    ${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg cacheDir}

    attempt=0
    while [ "$attempt" -lt 50 ]; do
      outputs="$(${awww} query 2>/dev/null || true)"
      if [ -n "$outputs" ]; then
        exec ${awww} img ${lib.escapeShellArg (toString cfg.wallpaper)}
      fi

      attempt=$((attempt + 1))
      ${pkgs.coreutils}/bin/sleep 0.2
    done

    echo "Timed out waiting for awww outputs before setting wallpaper" >&2
    exit 1
  '';
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
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${lib.escapeShellArg cacheDir}";
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
        # awww may start before niri finishes advertising outputs after reloads.
        ExecStart = "${wallpaperSetter}";
      };
      Install.WantedBy = [ "swww.service" ];
    };
  };
}
