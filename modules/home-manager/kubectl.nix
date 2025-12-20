# modules/home-manager/kubectl.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.within.kubectl;
in
{
  options.within.kubectl.enable = lib.mkEnableOption "Enables kubectl";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.kubectl ];
  };
}
