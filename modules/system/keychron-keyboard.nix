# Keychron keyboard support for Launcher/VIA WebHID access.
{
  lib,
  pkgs,
  config,
  ...
}:

let
  cfg = config.local.keychron-keyboard;
in
{
  options.local.keychron-keyboard = {
    enable = lib.mkEnableOption "Keychron keyboard udev rules for Launcher/VIA access";
  };

  config = lib.mkIf cfg.enable {
    services.udev.packages = [
      pkgs.keychron-udev-rules
    ];
  };
}
