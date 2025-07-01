{
  pkgs,
  config,
  lib,
  ...
}:

with lib;
{

  options.within.fleetdeb.enable = mkEnableOption "Enables fleet";

  config = mkIf config.within.fleetdeb.enable (
    let
      fleet = pkgs.callPackage ./fleet-default.nix { };
      startPreScript = pkgs.writeScript "init-falcon" ''
        #!${pkgs.bash}/bin/sh
        # Create the target directory
        mkdir -p /opt/fleet

        # Symlink the contents of the fleet package
        ln -sf ${fleet}/opt/fleet/* /opt/fleet
      '';
    in
    {

      systemd.services.fleetscript = {
        enable = true;
        description = "Fleet Script";
        unitConfig.DefaultDependencies = false;
        after = [ "local-fs.target" ];
        conflicts = [ "shutdown.target" ];
        before = [
          "sysinit.target"
          "shutdown.target"
        ];
        serviceConfig = {
          # ExecStartPre = "${startPreScript}";
          ExecStart = "${startPreScript}";
          Type = "forking";
          # PIDFile = "/run/fleetprescript.pid";
          Restart = "no";
          TimeoutStopSec = "60s";
          KillMode = "process";
        };
        wantedBy = [ "multi-user.target" ];
      };
    }
  );
}
