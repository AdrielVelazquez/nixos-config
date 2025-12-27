# modules/home-manager/thunderbird.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.within.thunderbird;
in
{
  options.within.thunderbird.enable = lib.mkEnableOption "Enables Thunderbird";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.thunderbird ];
  };
}
