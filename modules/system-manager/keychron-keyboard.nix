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
  options.local.keychron-keyboard = {
    enable = lib.mkEnableOption "Keychron keyboard udev rules for Keychron Launcher";

    inputGroupFallback = lib.mkEnableOption "input group access for Keychron Launcher hidraw devices";
  };

  config = lib.mkIf cfg.enable {
    environment.etc."udev/rules.d/69-keychron.rules" =
      if cfg.inputGroupFallback then
        {
          text = ''
            # Based on ${pkgs.keychron-udev-rules}/lib/udev/rules.d/69-keychron.rules
            KERNEL=="hidraw*", SUBSYSTEM=="hidraw", ATTRS{idVendor}=="3434", MODE="0660", GROUP="input", TAG+="uaccess"
            KERNEL=="event*", SUBSYSTEM=="input", ENV{ID_VENDOR_ID}=="3434", ENV{ID_INPUT_JOYSTICK}=="*?", ENV{ID_INPUT_JOYSTICK}=""
          '';
        }
      else
        {
          source = "${pkgs.keychron-udev-rules}/lib/udev/rules.d/69-keychron.rules";
        };
  };
}
