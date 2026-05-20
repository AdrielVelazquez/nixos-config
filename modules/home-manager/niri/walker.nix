# modules/home-manager/niri/walker.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  steamWalker = lib.hiPrio (
    pkgs.writeShellScriptBin "steam" ''
      # Route Steam through a shell-style launch path Walker can start reliably.
      ${pkgs.coreutils}/bin/sleep 1
      exec ${pkgs.coreutils}/bin/env \
        -u DESKTOP_STARTUP_ID \
        -u XDG_ACTIVATION_TOKEN \
        /run/current-system/sw/bin/steam "$@"
    ''
  );
in
{
  options.local.niri.walker.enable = lib.mkEnableOption "Walker application launcher";

  config = lib.mkIf (cfg.enable && cfg.walker.enable) {
    home.packages = [ steamWalker ];

    programs.walker = {
      enable = true;
      runAsService = true;
      config = {
        installed_providers = [
          "desktopapplications"
          "calc"
        ];
        providers = {
          default = [
            "desktopapplications"
            "calc"
          ];
          empty = [
            "desktopapplications"
            "calc"
          ];
        };
      };
    };

    systemd.user.services.walker.Service.Environment = lib.mkAfter [
      "GSK_RENDERER=cairo"
      "LIBGL_ALWAYS_SOFTWARE=1"
    ];

    # Keep Steam visible in the only enabled Walker provider while still using
    # the shell-style wrapper that launches reliably under Niri.
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
        noDisplay = false;
      };
    };
  };
}
