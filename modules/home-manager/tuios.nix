{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.tuios;
in
{
  options.local.tuios = {
    enable = lib.mkEnableOption "TUIOS terminal window manager";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.tuios ];
  };
}
