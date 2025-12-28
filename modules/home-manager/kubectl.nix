# modules/home-manager/kubectl.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.kubectl;
in
{
  options.local.kubectl.enable = lib.mkEnableOption "Enables kubectl";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.kubectl ];
  };
}
