# Keychron Launcher support on NixOS.

{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.keychron-keyboard;
in

{
  options.local.keychron-keyboard.enable = lib.mkEnableOption "Keychron keyboard udev rules for Keychron Launcher";

  config = lib.mkIf cfg.enable {
    services.udev.packages = [ pkgs.keychron-udev-rules ];
  };
}
