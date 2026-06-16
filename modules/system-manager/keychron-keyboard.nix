# Keychron Launcher support for non-NixOS Linux via system-manager.

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
    environment.etc."udev/rules.d/69-keychron.rules".source =
      "${pkgs.keychron-udev-rules}/lib/udev/rules.d/69-keychron.rules";
  };
}
