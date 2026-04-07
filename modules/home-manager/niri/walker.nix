# modules/home-manager/niri/walker.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  steamWalker = lib.hiPrio (pkgs.writeShellScriptBin "steam" ''
    # Route Steam through a shell-style launch path Walker can start reliably.
    ${pkgs.coreutils}/bin/sleep 1
    exec ${pkgs.coreutils}/bin/env \
      -u DESKTOP_STARTUP_ID \
      -u XDG_ACTIVATION_TOKEN \
      /run/current-system/sw/bin/steam "$@"
  '');
in
{
  options.local.niri.walker.enable = lib.mkEnableOption "Walker application launcher";

  config = lib.mkIf (cfg.enable && cfg.walker.enable) {
    home.packages = [ steamWalker ];

    programs.walker = {
      enable = true;
      runAsService = true;
      config = {
        providers = {
          default = [
            "windows"
            "runner"
            "desktopapplications"
            "calc"
            "websearch"
          ];
          empty = [
            "desktopapplications"
            "windows"
          ];
        };
      };
    };

    systemd.user.services.walker.Service.Environment = lib.mkAfter [
      "GSK_RENDERER=cairo"
      "LIBGL_ALWAYS_SOFTWARE=1"
    ];

    # Hide Steam from desktop-app matching so Walker prefers the runner result,
    # which uses the shell-style wrapper above instead of the .desktop path.
    xdg.desktopEntries = lib.optionalAttrs pkgs.stdenv.isLinux {
      steam = {
        name = "Steam";
        comment = "Application for managing and playing games on Steam";
        exec = "${lib.getExe steamWalker} %U";
        icon = "steam";
        terminal = false;
        type = "Application";
        mimeType = [
          "x-scheme-handler/steam"
          "x-scheme-handler/steamlink"
        ];
        startupNotify = false;
        noDisplay = true;
      };
    };
  };
}
