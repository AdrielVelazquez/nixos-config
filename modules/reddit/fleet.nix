{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.fleet;
in
{
  options.within.fleet.enable = mkEnableOption "Enables fleet Settings";
  config = mkIf cfg.enable {
    services.fleet = {
      enable = true;
    };
  };
}
