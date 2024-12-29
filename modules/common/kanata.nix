{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

with lib;

let
  cfg = config.within.kanata;
in
{
  options.within.kanata.enable = mkEnableOption "Enables kanata Settings";

  options.within.kanata.devices = mkOption {
    type = types.listOf types.str;
    default = [ ];
    description = "List of devices that changes the keyboard layout";
    example = [
      "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
      "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
    ];
  };
  config = mkIf cfg.enable {
    launchd = {
      user = {
        agents = {
          kanata-run = {
            enable = true;
            command = "/opt/homebrew/bin/kanata -c /Users/adriel.velazquez/.config/kanata";
            serviceConfig = {
              KeepAlive = true;
              RunAtLoad = true;
              StandardOutPath = "/tmp/kanata.out.log";
              StandardErrorPath = "/tmp/kanata.err.log";
            };
          };
        };
      };
    };
  };
}
