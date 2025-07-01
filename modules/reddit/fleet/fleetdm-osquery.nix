{
  pkgs,
  config,
  lib,
  ...
}:

with lib;
{

  options.within.fleet.enable = mkEnableOption "Enables fleet";

  config = mkIf config.within.fleet.enable {

    environment.systemPackages = with pkgs; [
      osquery
    ];

    services.osquery = {
      enable = true;
      flags = {
        # The enroll_secret_path expects a file path containing the secret.
        enroll_secret_path = config.sops.secrets.fleet_enroll_secret.path;
        # Flags for connecting osqueryd to Fleet
        # Corresponds to: --tls_hostname=reddit.cloud.fleetdm.com
        tls_hostname = builtins.readFile config.sops.secrets.fleet_url.path;
        # Endpoints for Fleet's services
        # Corresponds to: --config_plugin=tls
        # config_plugin = "tls";
        # Corresponds to: --config_tls_endpoint=/api/v1/osquery/config
        config_tls_endpoint = "/api/v1/osquery/config";
        tls_server_certs = "/opt/fleet/certs.pem";

        # Corresponds to: --logger_plugin=tls
        logger_plugin = "tls";
        # Corresponds to: --logger_tls_endpoint=/api/v1/osquery/log
        logger_tls_endpoint = "/api/v1/osquery/log";

        # Corresponds to: --enroll_tls_endpoint=/api/v1/osquery/enroll
        enroll_tls_endpoint = "/api/v1/osquery/enroll";

        # Enable running scripts
        # Corresponds to: --enable_scripts=true
        enable_scripts = "true";

        # Additional recommended flags for performance and stability
        host_identifier = "uuid";
        disable_audit = "false";
        audit_allow_config = "true";
        watchdog_level = "2";

        # Settings for Fleet's live query functionality
        disable_distributed = "false";
        distributed_plugin = "tls";
        distributed_interval = "10";
        distributed_tls_max_attempts = "3";
        distributed_tls_read_endpoint = "/api/v1/osquery/distributed/read";
        distributed_tls_write_endpoint = "/api/v1/osquery/distributed/write";
      };
    };
  };
}
