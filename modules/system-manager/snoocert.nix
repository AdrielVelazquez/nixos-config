# modules/system-manager/snoocert.nix
# Trusts the snoodev CA certificate at the system level.
# The cert itself is decrypted by sops in home-manager; this module
# picks it up from the user's cert directory and anchors it.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.snoocert;
in
{
  options.local.snoocert = {
    enable = lib.mkEnableOption "Trust snoodev CA certificate system-wide";

    certPath = lib.mkOption {
      type = lib.types.str;
      description = "Path to the snoodev CA certificate (decrypted by home-manager sops)";
    };

    distro = lib.mkOption {
      type = lib.types.enum [
        "arch"
        "debian"
      ];
      description = "Host distro, determines how the certificate is trusted system-wide";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.snoocert-trust = {
      description = "Trust snoodev CA certificate system-wide";

      serviceConfig =
        let
          script =
            if cfg.distro == "arch" then
              pkgs.writeShellScript "snoocert-trust" ''
                CERT="${cfg.certPath}"
                if [ ! -f "$CERT" ]; then
                  echo "Certificate not found at $CERT, skipping"
                  exit 0
                fi
                ${pkgs.p11-kit}/bin/trust anchor "$CERT"
                echo "snoodev CA certificate trusted (arch)"
              ''
            else
              pkgs.writeShellScript "snoocert-trust" ''
                CERT="${cfg.certPath}"
                if [ ! -f "$CERT" ]; then
                  echo "Certificate not found at $CERT, skipping"
                  exit 0
                fi
                cp "$CERT" /usr/local/share/ca-certificates/snoodev-ca.crt
                update-ca-certificates
                echo "snoodev CA certificate trusted (debian)"
              '';
        in
        {
          Type = "oneshot";
          ExecStart = script;
        };
    };

    systemd.paths.snoocert-trust = {
      description = "Watch snoodev CA certificate for trust updates";
      pathConfig = {
        PathExists = cfg.certPath;
        PathChanged = cfg.certPath;
        PathModified = cfg.certPath;
      };
      wantedBy = [ "multi-user.target" ];
    };
  };
}
