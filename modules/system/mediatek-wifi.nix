# modules/system/mediatek-wifi.nix
# MT7925 workarounds: disable power management, fix 6GHz, handle suspend
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
    boot.extraModprobeConfig = ''
      options mt7925e disable_aspm=1
      options mt7925-common disable_clc=1
    '';

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

    # Restart NetworkManager after suspend to clear stale driver state
    systemd.services.mediatek-wifi-resume-fix = {
      description = "Restart NetworkManager after suspend to fix MediaTek WiFi";
      wantedBy = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      after = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.systemd}/bin/systemctl restart NetworkManager.service";
      };
    };
  };
}
