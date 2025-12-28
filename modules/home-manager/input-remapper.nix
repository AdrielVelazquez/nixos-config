# modules/home-manager/input-remapper.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.input-remapper;
in
{
  options.local.input-remapper.enable = lib.mkEnableOption "Enables input-remapper";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.input-remapper ];
  };
}
