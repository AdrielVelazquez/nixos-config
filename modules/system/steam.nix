{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.steam;
in
{
  options.within.steam.enable = mkEnableOption "Enables Steam Settings";
  # Steam does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    programs.steam = {
      enable = true;
    };
  };
}
