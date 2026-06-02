# Apple Studio Display brightness support via asdbctl.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.apple-studio-display-brightness;
in
{
  options.local.apple-studio-display-brightness.enable = lib.mkEnableOption "Apple Studio Display brightness control";

  config = lib.mkIf cfg.enable {
    environment.etc."udev/rules.d/20-asd-backlight.rules".text = ''
      # MANAGED BY SYSTEM-MANAGER
      # Allow regular user access to Apple Studio Display brightness controls.
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="1114", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="1116", MODE="0660", TAG+="uaccess"
      SUBSYSTEM=="hidraw", KERNEL=="hidraw*", ATTRS{idVendor}=="05ac", ATTRS{idProduct}=="1118", MODE="0660", TAG+="uaccess"
    '';
  };
}
