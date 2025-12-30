# modules/system-manager/kanata.nix
# System-manager Kanata keyboard remapper (for non-NixOS Linux like PopOS)
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

  # Generate device config lines
  deviceCfgLines = lib.concatMapStringsSep "\n" (device: "  linux-dev ${device}") cfg.devices;

  # Combine defcfg with shared layout
  fullKanataConfig = ''
    (defcfg
      process-unmapped-keys yes
    ${deviceCfgLines}
    )

    ${layoutConfig}
  '';

  kanataConfigFile = pkgs.writeText "kanata.kbd" fullKanataConfig;
in
{
  options.local.kanata = {
    enable = lib.mkEnableOption "Enables Kanata keyboard remapper";

    devices = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of devices for keyboard remapping";
      example = [
        "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.kanata ];

    # System-level systemd service (runs as root)
    systemd.services.kanata = {
      description = "Kanata keyboard remapper";

      serviceConfig = {
        ExecStart = "${pkgs.kanata}/bin/kanata --cfg ${kanataConfigFile}";
        Restart = "always";
        RestartSec = 1;
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
