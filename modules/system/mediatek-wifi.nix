# modules/system/mediatek-wifi.nix
# MediaTek MT7925 WiFi/Bluetooth stability fixes
#
# Known issues with MT7925:
# - Power management causes random disconnections
# - ASPM (PCIe power states) causes hangs
# - CLC (Country Location Code) causes 6GHz instability
# - WiFi often fails to reconnect after suspend
# - wpa_supplicant has issues; iwd works better
#
# References:
# - https://bugs.launchpad.net/ubuntu/+source/linux/+bug/2118755
# - https://github.com/robcohen/dotfiles (MT7925 workarounds)
{ config, lib, pkgs, ... }:

let
  cfg = config.within.mediatek-wifi;
in
{
  options.within.mediatek-wifi = {
    enable = lib.mkEnableOption "MediaTek MT7925 WiFi stability fixes";

    useIwd = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use iwd backend instead of wpa_supplicant (recommended for MT7925)";
    };
  };

  config = lib.mkIf cfg.enable {
    # =========================================================================
    # Kernel Module Parameters
    # =========================================================================
    # Disable power management at driver level (safe - happens during load)
    boot.extraModprobeConfig = ''
      # MT7925 WiFi - disable all power management for stability
      options mt7925e disable_aspm=1
      options mt7925e power_save=0

      # Disable CLC (Country Location Code) - fixes 6GHz stability
      options mt7925-common disable_clc=1
    '';

    # =========================================================================
    # NetworkManager Configuration
    # =========================================================================
    networking.networkmanager.wifi = {
      # Disable WiFi power saving
      powersave = false;

      # Consistent MAC during scans (randomization can cause issues)
      scanRandMacAddress = false;

      # Use iwd backend if enabled
      backend = lib.mkIf cfg.useIwd "iwd";
    };

    # =========================================================================
    # iwd Configuration (when useIwd = true)
    # =========================================================================
    networking.wireless.iwd = lib.mkIf cfg.useIwd {
      settings = {
        General = {
          # Consistent MAC per network (helps with WPA3 handshake)
          AddressRandomization = "network";
          # Let NetworkManager handle IP configuration, not iwd
          EnableNetworkConfiguration = false;
        };
        Settings = {
          AutoConnect = true;
        };
      };
    };

    # =========================================================================
    # Suspend/Resume Fix
    # =========================================================================
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
