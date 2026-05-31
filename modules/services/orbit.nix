# modules/services/orbit.nix
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.orbit;

  managedEnrollSecretPath = config.sops.secrets.${cfg.enrollSecretName}.path;
in
{
  options.local.orbit = {
    enable = lib.mkEnableOption "Fleet Orbit agent";

    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether the Orbit service should start automatically at boot.";
    };

    fleetUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://reddit.cloud.fleetdm.com";
      description = "The base URL of the Fleet server.";
    };

    enrollSecretPath = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = "/run/secrets/fleet_enroll_secret";
      description = ''
        Path to a file containing the Fleet enroll secret. When null, the
        module declares and uses the SOPS secret named by enrollSecretName.
      '';
    };

    enrollSecretName = lib.mkOption {
      type = lib.types.str;
      default = "fleet_enroll_secret";
      description = "SOPS secret key to use as the Orbit enroll secret.";
    };

    sopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/secrets-enc.yaml;
      description = "Path to the SOPS secrets file containing the Orbit enroll secret.";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops/age/keys.txt";
      description = "Path to the system age key file for SOPS decryption.";
    };

    desktop = {
      enable = lib.mkEnableOption "Fleet Desktop tray application";

      package = lib.mkPackageOption pkgs "fleet-desktop" { };

      alternativeBrowserHost = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Alternative host to use for Fleet Desktop browser URLs.";
      };
    };

    enableScripts = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Whether to enable Fleet script execution.";
    };

    debug = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Whether to enable Orbit debug logging.";
    };

    hostIdentifier = lib.mkOption {
      type = lib.types.nullOr (
        lib.types.enum [
          "uuid"
          "instance"
        ]
      );
      default = "uuid";
      description = "Host identifier mode to use when Orbit and osquery enroll to Fleet.";
    };

    insecure = lib.mkOption {
      type = lib.types.nullOr lib.types.bool;
      default = null;
      description = "Whether to disable TLS certificate verification.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.age.keyFile = lib.mkDefault cfg.ageKeyFile;

    sops.secrets = lib.mkIf (cfg.enrollSecretPath == null) {
      ${cfg.enrollSecretName} = {
        sopsFile = cfg.sopsFile;
      };
    };

    services.orbit = {
      enable = true;
      inherit (cfg)
        debug
        enableScripts
        fleetUrl
        hostIdentifier
        insecure
        ;
      desktop = {
        inherit (cfg.desktop)
          enable
          package
          alternativeBrowserHost
          ;
      };
      enrollSecretPath =
        if cfg.enrollSecretPath != null then cfg.enrollSecretPath else managedEnrollSecretPath;
    };

    systemd.services.orbit.wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
  };
}
