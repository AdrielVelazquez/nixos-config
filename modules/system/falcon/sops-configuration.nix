{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.soaps;
in
{
  options.within.soaps.enable = mkEnableOption "Enables plex Settings";
  # plex does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    sops.defaultSopsFile = /home/adriel/.config/sops/secrets.yaml;
    sops.age.keyFile = "/home/adriel/.config/sops/age/keys.txt";
    sops.age.sshKeyPaths = [ ];
    systemd.services.sops-nix.serviceConfig.SupplementaryGroups = [ "keys" ];

    systemd.services.sops-nix.serviceConfig.PermissionsStartOnly = true;
    systemd.services.sops-nix.serviceConfig.LoadCredential = [
      "age_key:/home/adriel/.config/sops/age/keys.txt"
    ];
    sops.secrets.falcon_customer_id = {
      # This secret is needed by a systemd service running as root
      owner = "root";
      group = "root";
      mode = "0400"; # Only readable by the owner (root)
    };
  };
}
