# modules/home-manager/niri/kanshi.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  awww = lib.getExe pkgs.awww;
  # Reapply the wallpaper after outputs change so newly enabled monitors
  # don't keep the solid-color background from the initial session startup.
  wallpaperExec =
    ''${pkgs.bash}/bin/bash -lc "sleep 0.5; ${awww} img ${lib.escapeShellArg (toString cfg.wallpaper)}"'';
in
{
  options.local.niri.kanshi.enable = lib.mkEnableOption "kanshi daemon";

  config = lib.mkIf (cfg.enable && cfg.kanshi.enable) {
    services.kanshi = {
      enable = true;
      settings = [
        {
          profile = {
            name = "undocked";
            outputs = [
              {
                criteria = "eDP-1";
                status = "enable";
                scale = 1.1; # Might want to adjust this scale for the Framework's 3:2 screen!
              }
            ];
            exec = [ wallpaperExec ];
          };
        }
        {
          profile = {
            name = "docked";
            outputs = [
              {
                criteria = "eDP-1";
                status = "disable"; # Turn off the laptop screen
              }
              {
                criteria = "*"; # Wildcard for external monitor
                status = "enable";
                scale = 1.0;
              }
            ];
            exec = [ wallpaperExec ];
          };
        }
      ];
    };
  };
}
