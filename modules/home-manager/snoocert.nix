# modules/home-manager/snoocert.nix
# Decrypts the snoodev CA cert via sops and adds it to the user NSS DB.
# System-level trust (trust anchor / update-ca-certificates) is handled by
# the system-manager snoocert module, which runs as root.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.snoocert;
  certDir = "${config.home.homeDirectory}/.config/certs";
  certPath = "${certDir}/snoodev-ca.crt";
in
{
  options.local.snoocert = {
    enable = lib.mkEnableOption "Install snoodev CA certificate from sops";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.snoocert = {
      path = certPath;
    };

    home.activation.installSnoocert = lib.hm.dag.entryAfter [
      "writeBoundary"
      "setupSopsAgeKey"
    ] ''
      SNOODEV_CA="${certPath}"

      if [ -f "$SNOODEV_CA" ]; then
        $DRY_RUN_CMD mkdir -p "$HOME/.pki/nssdb"
        $DRY_RUN_CMD ${pkgs.nss.tools}/bin/certutil -d sql:$HOME/.pki/nssdb -A -t TC -n snoodev-ca -i "$SNOODEV_CA"
        echo "snoodev CA added to user NSS DB"
      else
        echo "WARNING: $SNOODEV_CA not found, skipping cert install"
      fi
    '';
  };
}
