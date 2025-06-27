{
  pkgs,
  config,
  lib,
  ...
}:

with lib;
{
  imports = [
    ./sops-configuration.nix
  ];

  options.within.falcon.enable = mkEnableOption "Enables falcon Settings";

  # The config block is now conditional.
  config = mkIf config.within.falcon.enable (
    # The `let` block is now part of an expression that `mkIf` evaluates.
    # It is no longer inside the attribute set's curly braces.
    let
      falcon = pkgs.callPackage ./falcon-default.nix { };
      falconCidFile = config.sops.secrets.falcon_customer_id.path;
      startPreScript = pkgs.writeScript "init-falcon" ''
        #! ${pkgs.bash}/bin/sh
        /run/current-system/sw/bin/mkdir -p /opt/CrowdStrike
        ln -sf ${falcon}/opt/CrowdStrike/* /opt/CrowdStrike
        ${falcon}/bin/fs-bash -c "${falcon}/opt/CrowdStrike/falconctl -s --cid=$(cat ${falconCidFile}) -f"
      '';
    in
    # The `in` block returns the final attribute set containing all our options.
    {
      within.sops.enable = true;

      systemd.services.falcon-sensor = {
        enable = true;
        description = "CrowdStrike Falcon Sensor";
        unitConfig.DefaultDependencies = false;
        after = [ "local-fs.target" ];
        conflicts = [ "shutdown.target" ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        serviceConfig = {
          ExecStartPre = "${startPreScript}";
          ExecStart = "${falcon}/bin/fs-bash -c \"${falcon}/opt/CrowdStrike/falcond\"";
          Type = "forking";
          PIDFile = "/run/falcond.pid";
          Restart = "no";
          TimeoutStopSec = "60s";
          KillMode = "process";
        };
        wantedBy = [ "multi-user.target" ];
      };
    }
  ); # <-- The closing parenthesis for the mkIf argument
}
