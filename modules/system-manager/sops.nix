# modules/system-manager/sops.nix
#
# Root-scoped sops-nix defaults for non-NixOS hosts managed by system-manager.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.sops;
in
{
  options.local.sops = {
    enable = lib.mkEnableOption "sops-nix for system-manager";

    defaultSopsFile = lib.mkOption {
      type = lib.types.path;
      default = ../../secrets/secrets-enc.yaml;
      description = "Default SOPS file to use for system-managed secrets.";
    };

    ageKeyFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sops/age/keys.txt";
      description = "Root-readable age key file used to decrypt system-managed secrets.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."sysusers.d/sops-nix.conf".text = ''
      g keys - -
    '';

    sops = {
      defaultSopsFile = cfg.defaultSopsFile;
      useSystemdActivation = true;

      age = {
        keyFile = cfg.ageKeyFile;
        sshKeyPaths = [ ];
        generateKey = false;
      };
    };

    environment.systemPackages = [
      pkgs.sops
    ];
  };
}
