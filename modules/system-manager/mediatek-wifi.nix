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
