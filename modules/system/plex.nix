{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.plex;
in
{
  options.within.plex.enable = mkEnableOption "Enables plex Settings";
  # plex does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    programs.plex = {
      enable = true;
      openFirewall = true;
    };
    services.plex = {
      enable = true;
      openFirewall = true;
      user = "adriel";
    };
  };
}
