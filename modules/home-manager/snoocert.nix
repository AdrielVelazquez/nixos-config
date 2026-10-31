# modules/home-manager/snoocert.nix
# Decrypts the snoodev CA cert via sops and adds it to the user NSS DB.
# System-level trust is handled separately by the host's root-scoped module.
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
  importer = pkgs.writeShellApplication {
    name = "snoocert-import";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.nss.tools
      pkgs.openssl
    ];
    text = builtins.readFile ./snoocert-import.sh;
  };
in
{
  options.local.snoocert = {
    enable = lib.mkEnableOption "Install snoodev CA certificate from sops";
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.snoocert = {
      path = certPath;
    };

    systemd.user.services.snoocert-trust = {
      Unit = {
        Description = "Import corporate CA into the user NSS database";
        After = [ "sops-nix.service" ];
        Requires = [ "sops-nix.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${lib.getExe importer} ${lib.escapeShellArg certPath} ${lib.escapeShellArg "${config.home.homeDirectory}/.pki/nssdb"}";
      };
      Install.WantedBy = [ "default.target" ];
    };
    systemd.user.paths.snoocert-trust = {
      Unit.Description = "Watch corporate CA changes for NSS trust";
      Path.PathChanged = certDir;
      Install.WantedBy = [ "default.target" ];
    };
  };
}
