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

    environment.etc."systemd/system-sleep/99-mediatek-wifi" = {
      mode = "0755";
      text = ''
        #!${pkgs.runtimeShell}
        # MANAGED BY SYSTEM-MANAGER

        case "$1" in
          pre)
            ${pkgs.systemd}/bin/systemctl stop NetworkManager.service
            ${pkgs.systemd}/bin/systemctl stop wpa_supplicant.service
            ;;
          post)
            ${pkgs.systemd}/bin/systemctl start wpa_supplicant.service
            ${pkgs.systemd}/bin/systemctl start NetworkManager.service
            ;;
        esac
      '';
    };
  };
}
