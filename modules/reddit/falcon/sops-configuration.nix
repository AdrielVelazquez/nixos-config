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
  options.within.sops.enable = mkEnableOption "Enables plex Settings";
  # plex does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    sops.defaultSopsFile = ./secrets.yaml;
    sops.age.keyFile = "./keys.txt";
    sops.age.sshKeyPaths = [ ];
    systemd.services.sops-nix.serviceConfig.SupplementaryGroups = [ "keys" ];

    systemd.services.sops-nix.serviceConfig.PermissionsStartOnly = true;
    systemd.services.sops-nix.serviceConfig.LoadCredential = [
      "age_key:./keys.txt"
    ];
    sops.secrets.falcon_customer_id = {
      # This secret is needed by a systemd service running as root
      owner = "root";
      group = "root";
      mode = "0400"; # Only readable by the owner (root)
    };
  };
}
