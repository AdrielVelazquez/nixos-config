# modules/system-manager/mediatek-wifi.nix
# MediaTek MT7925 WiFi stability fixes for non-NixOS systems
# Simple version - just config files, no iwd
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.mediatek-wifi;
in
{
  options.local.mediatek-wifi = {
    enable = lib.mkEnableOption "MediaTek MT7925 WiFi stability fixes";
  };

  config = lib.mkIf cfg.enable {
    # =========================================================================
    # Modprobe config - kernel module parameters
    # Note: Takes effect on next boot (or manual module reload)
    # =========================================================================
    environment.etc."modprobe.d/mediatek-wifi.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER - DO NOT EDIT
      # MT7925 WiFi - disable power management for stability
      options mt7925e disable_aspm=1
      options mt7925e power_save=0

      # Disable CLC (Country Location Code) - fixes 6GHz stability
      options mt7925-common disable_clc=1
    '';

    # =========================================================================
    # NetworkManager config - disable WiFi power saving
    # =========================================================================
    environment.etc."NetworkManager/conf.d/99-mediatek-wifi.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER - DO NOT EDIT
      [connection]
      wifi.powersave = 2

      [device]
      wifi.scan-rand-mac-address = no
    '';

    # =========================================================================
    # Resume Fix - restart NetworkManager after suspend
    # =========================================================================
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


