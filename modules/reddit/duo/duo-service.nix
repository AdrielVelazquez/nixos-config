{
  pkgs,
  config,
  lib,
  ...
}:

with lib;
{

  options.within.duodesktop.enable = mkEnableOption "Enables duo-desktop";

  config = mkIf config.within.duodesktop.enable (
    let
      duoDesktop = pkgs.callPackage ./duo-default.nix { };
    in
    {
      systemd.services.duo-desktop = {
        description = "Duo Desktop";
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          # The path should point to the executable within the Nix store.
          ExecStart = "${duoDesktop}/bin/dd-bash -c \"${duoDesktop}/opt/duo/duo-desktop/duo-desktop\"";
          Restart = "on-failure";
          NoNewPrivileges = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          RestrictRealtime = true;
          ProtectControlGroups = true;
          RestrictSUIDSGID = true;
          LockPersonality = true;
          SystemCallErrorNumber = "EPERM";

          # This line was causing the conflict and has been removed.
          # RestrictNamespaces = true;

          CapabilityBoundingSet = [
            "CAP_DAC_OVERRIDE"
            "CAP_NET_ADMIN"
            "CAP_NET_RAW"
            "CAP_SYS_ADMIN"
            "CAP_SYS_PTRACE"
          ];

          RestrictAddressFamilies = [
            "AF_UNIX"
            "AF_LOCAL"
            "AF_INET"
            "AF_NETLINK"
            "AF_INET6"
          ];

          SystemCallFilter = [
            "~@clock"
            "@cpu-emulation"
            "@debug"
            "@module"
            "@mount"
            "@obsolete"
            "@privileged"
            "@raw-io"
            "@reboot"
            "@swap"
          ];
        };
      };
    }
  );
}
