{
  pkgs,
  config,
  lib,
  ...
}:

with lib;
{

  options.within.falcon.enable = mkEnableOption "Enables falcon Settings";

  config = mkIf config.within.falcon.enable (
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
    {
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
  );
}
