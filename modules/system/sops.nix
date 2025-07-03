{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.sops;
in
{
  options.within.sops.enable = mkEnableOption "Enables sops";
  config = mkIf cfg.enable {
    sops.defaultSopsFile = ./secrets-enc.yaml;
    sops.age.keyFile = "/var/lib/sops/age/keys.txt";
    sops.age.sshKeyPaths = [ ];
    systemd.services.sops-nix.serviceConfig.SupplementaryGroups = [ "keys" ];

    systemd.services.sops-nix.serviceConfig.PermissionsStartOnly = true;
    systemd.services.sops-nix.serviceConfig.LoadCredential = [
      "age_key:/var/lib/sops/age/keys.txt"
    ];
    sops.secrets.falcon_customer_id = {
      # This secret is needed by a systemd service running as root
      owner = "root";
      group = "root";
      mode = "0400"; # Only readable by the owner (root)
    };

    sops.secrets.fleet_enroll_secret = {
      owner = "root";
      group = "root";
      mode = "0400"; # Only readable by the owner (root)
    };

    # sops.secrets.fleet_url = {
    #   owner = "root";
    #   group = "root";
    #   mode = "0400"; # Only readable by the owner (root)
    # };
  };
}
