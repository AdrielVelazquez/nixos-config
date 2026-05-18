# modules/home-manager/niri/wallpaper.nix
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
  options.local.niri = {
    awww.enable = lib.mkEnableOption "awww wallpaper daemon";
    swww.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Deprecated compatibility alias for local.niri.awww.enable.";
    };
  };

  config = lib.mkIf (cfg.enable && (cfg.awww.enable || cfg.swww.enable)) {
    warnings = lib.optional cfg.swww.enable ''
      local.niri.swww.enable is deprecated. Use local.niri.awww.enable instead.
    '';

    systemd.user.services.awww = {
      Unit = {
        Description = "awww wallpaper daemon";
        Conflicts = [ "swww.service" ];
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

    systemd.user.services.awww-wallpaper = {
      Unit = {
        Description = "Set wallpaper via awww";
        After = [ "awww.service" ];
        Requires = [ "awww.service" ];
        PartOf = [ "awww.service" ];
      };
      Service = {
        Type = "oneshot";
        # awww may start before niri finishes advertising outputs after reloads.
        ExecStart = "${wallpaperSetter}";
      };
      Install.WantedBy = [ "awww.service" ];
    };
  };
}
