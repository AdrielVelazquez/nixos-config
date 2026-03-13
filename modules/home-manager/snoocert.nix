# modules/home-manager/snoocert.nix
{
  lib,
  config,
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

    distro = lib.mkOption {
      type = lib.types.enum [
        "arch"
        "debian"
      ];
      description = "Host distro, determines how the certificate is trusted system-wide";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.snoocert = {
      path = certPath;
    };

    home.activation.installSnoocert = lib.hm.dag.entryAfter [
      "writeBoundary"
      "setupSopsAgeKey"
    ] (
      if cfg.distro == "arch" then
        ''
          SNOODEV_CA="${certPath}"

          if [ -f "$SNOODEV_CA" ]; then
            $DRY_RUN_CMD sudo trust anchor "$SNOODEV_CA"
            echo "snoodev CA certificate trusted (arch)"
          else
            echo "WARNING: $SNOODEV_CA not found, skipping trust anchor"
          fi
        ''
      else
        ''
          SNOODEV_CA="${certPath}"

          if [ -f "$SNOODEV_CA" ]; then
            if ! command -v certutil >/dev/null 2>&1; then
              $DRY_RUN_CMD sudo apt-get install -y libnss3-tools
            fi

            $DRY_RUN_CMD certutil -d sql:$HOME/.pki/nssdb -A -t TC -n snoodev-ca -i "$SNOODEV_CA"
            $DRY_RUN_CMD sudo cp "$SNOODEV_CA" /usr/local/share/ca-certificates/
            $DRY_RUN_CMD sudo update-ca-certificates
            echo "snoodev CA certificate trusted (debian)"
          else
            echo "WARNING: $SNOODEV_CA not found, skipping cert install"
          fi
        ''
    );
  };
}
