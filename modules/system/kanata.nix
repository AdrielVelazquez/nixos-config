# modules/system/kanata.nix
# System-level Kanata keyboard remapper for NixOS
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.kanata;

  # Read shared layout from dotfiles
  layoutConfig = builtins.readFile ../../dotfiles/kanata/layout.kbd;
in
{
  options.local.kanata = {
    enable = lib.mkEnableOption "Enables Kanata keyboard remapper";

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of input devices for keyboard remapping";
      example = [
        "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
        "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
      ];
    };

    extraGroups = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional groups for the kanata service (e.g., for openrazer compatibility)";
      example = [ "openrazer" ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.kanata ];

    # Add supplementary groups to the kanata service if specified
    systemd.services.kanata-internalKeyboard.serviceConfig.SupplementaryGroups = lib.mkIf (
      cfg.extraGroups != [ ]
    ) cfg.extraGroups;

    services.kanata = {
      enable = true;
      keyboards.internalKeyboard = {
        devices = cfg.devices;
        extraDefCfg = "process-unmapped-keys yes";
        config = layoutConfig;
      };
    };
  };
}
