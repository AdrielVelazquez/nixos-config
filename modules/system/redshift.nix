# modules/system/redshift.nix
{ lib, config, ... }:

let
  cfg = config.within.redshift;
in
{
  options.within.redshift.enable = lib.mkEnableOption "Enables Redshift screen color temperature";

  config = lib.mkIf cfg.enable {
    location.provider = "geoclue2";

    services.redshift = {
      enable = true;
      brightness = {
        day = "1";
        night = "1";
      };
      temperature = {
        day = 4200;
        night = 2200;
      };
    };
  };
}
