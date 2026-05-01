# modules/home-manager/zoom.nix
#
# Plain Zoom Linux client. No wrappers, no portal overrides, no config
# seeding -- just `pkgs.zoom-us` as shipped by nixpkgs.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.zoom;
in
{
  options.local.zoom = {
    enable = lib.mkEnableOption "Zoom Linux client";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.zoom-us ];
  };
}
