# Native bolt setup for non-NixOS hosts managed by system-manager.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.bolt;

  setupScript = pkgs.writeShellScript "setup-bolt" ''
    set -euo pipefail

    /usr/bin/pacman -S --needed --noconfirm bolt
    /usr/bin/systemctl start bolt.service
  '';
in
{
  options.local.bolt = {
    enable = lib.mkEnableOption "native bolt Thunderbolt authorization service";

    disableThunderboltHostReset = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Set thunderbolt.host_reset=false via modprobe.d.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."modprobe.d/99-thunderbolt-studio-display.conf" =
      lib.mkIf cfg.disableThunderboltHostReset
        {
          text = ''
            # MANAGED BY SYSTEM-MANAGER
            # Avoid USB4 host-router resets tearing down the Apple Studio Display DP tunnel.
            options thunderbolt host_reset=false
          '';
        };

    systemd.services.setup-bolt = {
      description = "Install and start native bolt Thunderbolt authorization service";
      after = [
        "dbus.service"
        "systemd-udevd.service"
      ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        ExecStart = setupScript;
        RemainAfterExit = true;
      };
    };
  };
}
