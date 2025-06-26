{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.redshift;
in
{
  options.within.redshift.enable = mkEnableOption "Enables redshift Settings";
  config = mkIf cfg.enable {

    location.provider = "geoclue2";
    services.redshift = {
      enable = true;
      brightness = {
        # Note the string values below.
        day = "1";
        night = "1";
      };
      temperature = {
        day = 4200;
        night = 3700;
      };
    };
  };
}
