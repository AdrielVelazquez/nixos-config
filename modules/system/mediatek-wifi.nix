# modules/system/mediatek-wifi.nix
# MT7925 tweaks: keep suspend recovery and optional iwd backend.
# https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2118755
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.mediatek-wifi;
in
{
  options.local.mediatek-wifi = {
    enable = lib.mkEnableOption "MediaTek MT7925 WiFi stability fixes";

    useIwd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use iwd backend instead of wpa_supplicant (recommended for MT7925)";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.networkmanager.wifi = {
      powersave = false;
      scanRandMacAddress = false;
      backend = lib.mkIf cfg.useIwd "iwd";
    };

    networking.wireless.iwd = lib.mkIf cfg.useIwd {
      settings = {
        General = {
          AddressRandomization = "network";
          EnableNetworkConfiguration = false;
        };
        Settings = {
          AutoConnect = true;
        };
      };
    };

    # Restart NetworkManager after resume to clear stale driver state
    systemd.services.mediatek-wifi-resume-fix = {
      description = "Restart NetworkManager after sleep to fix MediaTek WiFi";
      wantedBy = [
        "systemd-suspend.service"
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      after = [
        "systemd-suspend.service"
        "systemd-hibernate.service"
        "systemd-hybrid-sleep.service"
        "systemd-suspend-then-hibernate.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl try-restart NetworkManager.service";
      };
    };
  };
}
