# modules/home-manager/thunderbird.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.thunderbird;
in
{
  options.local.thunderbird.enable = lib.mkEnableOption "Enables Thunderbird";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.thunderbird ];
  };
}
