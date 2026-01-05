# modules/system-manager/mediatek-wifi.nix
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
    environment.etc."modprobe.d/mediatek-wifi.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      options mt7925e disable_aspm=1
      options mt7925e power_save=0
      options mt7925-common disable_clc=1
    '';

    environment.etc."NetworkManager/conf.d/99-mediatek-wifi.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      [connection]
      wifi.powersave = 2

      [device]
      wifi.scan-rand-mac-address = no
    '';

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
