# modules/system-manager/orbit.nix
#
# Fleet Orbit for non-NixOS hosts managed by system-manager.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.orbit;

  boolToStringOrNull = value: if value == null then null else lib.boolToString value;

  managedEnrollSecretPath = config.sops.secrets.${cfg.enrollSecretName}.path;

  nativeSudo = pkgs.runCommand "native-sudo" { } ''
    mkdir -p "$out/bin"
    ln -s /usr/bin/sudo "$out/bin/sudo"
  '';

  removeNativeOrbit = pkgs.writeShellScript "remove-native-orbit" ''
    set -euo pipefail

    removed=0
    for package in ${lib.escapeShellArgs cfg.archPackageNames}; do
      if /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
        removed=1
      fi
    done

    if [ "$removed" -eq 0 ]; then
      exit 0
    fi

    /usr/bin/systemctl stop orbit.service 2>/dev/null || true

    for package in ${lib.escapeShellArgs cfg.archPackageNames}; do
      if /usr/bin/pacman -Q "$package" >/dev/null 2>&1; then
        /usr/bin/pacman -R --noconfirm "$package"
      fi
    done

    /usr/bin/systemctl daemon-reload
  '';
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

    archPackageNames = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "fleet-osquery" ];
      description = "Native Arch packages to remove before starting the Nix-managed Orbit service.";
    };

    removeNativePackage = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to remove the native Arch Fleet Orbit package before starting the Nix service.";
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

    setupExperience = {
      enable = lib.mkEnableOption "the Fleet web setup experience" // {
        default = true;
      };

      browserPackage = lib.mkPackageOption pkgs "xdg-utils" { };
    };

    package = lib.mkPackageOption pkgs "fleet-orbit" { };

    osqueryPackage = lib.mkPackageOption pkgs "osquery" { };

    scriptPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        bash
        zsh
        python3
      ];
      description = "Interpreter packages added to the Orbit service path when scripts are enabled.";
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
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optional cfg.desktop.enable cfg.desktop.package;

    sops.secrets = lib.mkIf (cfg.enrollSecretPath == null) {
      ${cfg.enrollSecretName} = {
        sopsFile = cfg.sopsFile;
      };
    };

    systemd.services.remove-native-orbit = lib.mkIf cfg.removeNativePackage {
      description = "Remove native Arch Fleet Orbit package";
      before = [
        "orbit.service"
      ];
      wantedBy = lib.optional cfg.autoStart "multi-user.target";

      serviceConfig = {
        Type = "oneshot";
        ExecStart = removeNativeOrbit;
        RemainAfterExit = true;
      };
    };

    systemd.services.orbit = {
      enable = true;
      description = "Fleet Orbit agent";
      wantedBy = lib.optional cfg.autoStart "multi-user.target";
      after = [
        "network-online.target"
      ]
      ++ lib.optional (cfg.enrollSecretPath == null) "sops-install-secrets.service"
      ++ lib.optional cfg.removeNativePackage "remove-native-orbit.service";
      wants = [ "network-online.target" ];
      requires = lib.optional (cfg.enrollSecretPath == null) "sops-install-secrets.service";

      environment = lib.filterAttrs (_: value: value != null) {
        ORBIT_FLEET_URL = cfg.fleetUrl;
        ORBIT_ENROLL_SECRET_PATH = "%d/enroll-secret";
        ORBIT_FLEET_CERTIFICATE =
          if cfg.insecure == true then null else "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        ORBIT_DEBUG = boolToStringOrNull cfg.debug;
        ORBIT_ENABLE_SCRIPTS = boolToStringOrNull cfg.enableScripts;
        ORBIT_HOST_IDENTIFIER = cfg.hostIdentifier;
        ORBIT_INSECURE = boolToStringOrNull cfg.insecure;
        ORBIT_FLEET_DESKTOP_ALTERNATIVE_BROWSER_HOST = cfg.desktop.alternativeBrowserHost;

        ORBIT_DISABLE_KEYSTORE = "true";
        ORBIT_DISABLE_SETUP_EXPERIENCE = lib.boolToString (!cfg.setupExperience.enable);
        ORBIT_DISABLE_UPDATES = "true";
        ORBIT_FLEET_DESKTOP = lib.boolToString cfg.desktop.enable;
        ORBIT_LOG_FILE = "/var/log/orbit/orbit.log";
        ORBIT_OSQUERY_DB = "/var/lib/orbit/osquery.db";
        ORBIT_ROOT_DIR = "/var/lib/orbit";
        ORBIT_OSQUERYD_PATH = lib.getExe' cfg.osqueryPackage "osqueryd";
        ORBIT_OSQUERY_LOG_PATH = "/var/log/orbit/osquery";
        ORBIT_DESKTOP_PATH = if cfg.desktop.enable then lib.getExe cfg.desktop.package else null;
        ORBIT_BROWSER_PATH =
          if cfg.setupExperience.enable then
            lib.getExe' cfg.setupExperience.browserPackage "xdg-open"
          else
            null;
      };

      path =
        lib.optionals cfg.desktop.enable [ nativeSudo ]
        ++ lib.optionals (cfg.enableScripts == true) cfg.scriptPackages;

      serviceConfig = {
        ExecStart = lib.getExe cfg.package;
        LoadCredential = [
          "enroll-secret:${
            if cfg.enrollSecretPath != null then cfg.enrollSecretPath else managedEnrollSecretPath
          }"
        ];
        StateDirectory = "orbit";
        LogsDirectory = "orbit";
        Restart = "always";
        RestartSec = 60;
      };
    };
  };
}
