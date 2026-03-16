# modules/home-manager/niri/kanshi.nix
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
          };
        }
      ];
    };
  };
}
