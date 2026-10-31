{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.snoocert;
  bundlePath = "/run/snoocert/ca-bundle.crt";
in
{
  options.local.snoocert.enable = lib.mkEnableOption "runtime corporate CA trust from SOPS";

  config = lib.mkIf cfg.enable {
    sops.secrets.snoocert.restartUnits = [ "snoocert-trust.service" ];

    # certificateFiles is build-time input; the decrypted certificate must never enter the store.
    environment.etc =
      lib.genAttrs
        [
          "ssl/certs/ca-certificates.crt"
          "ssl/certs/ca-bundle.crt"
          "pki/tls/certs/ca-bundle.crt"
        ]
        (_: {
          source = lib.mkForce bundlePath;
        });

    systemd.services.snoocert-trust = {
      description = "Assemble system CA bundle with runtime corporate certificate";
      wantedBy = [ "sysinit.target" ];
      before = [
        "sysinit.target"
        "network-pre.target"
        "nix-daemon.service"
      ];
      after = [
        "local-fs.target"
        "sops-install-secrets.service"
      ];
      requires = [ "sops-install-secrets.service" ];
      unitConfig.DefaultDependencies = false;
      path = [
        pkgs.coreutils
        pkgs.openssl
      ];
      script = ''
        ${pkgs.bash}/bin/bash ${./snoocert-bundle.sh} \
          ${config.security.pki.caBundle} \
          ${lib.escapeShellArg config.sops.secrets.snoocert.path} \
          ${bundlePath}
      '';
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "snoocert";
        RuntimeDirectoryMode = "0755";
      };
    };
  };
}
