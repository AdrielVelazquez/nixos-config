# modules/home-manager/zoom.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.within.zoom;
in
{
  options.within.zoom.enable = lib.mkEnableOption "Enables Zoom";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.zoom-us ];
  };
}
