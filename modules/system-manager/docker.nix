# modules/system-manager/docker.nix
#
# system-manager doesn't expose `virtualisation.docker`, so we hand-roll the
# systemd unit. Mirrors the option surface of modules/services/docker.nix
# at the bare minimum (just an `enable` flag for now).
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.docker;
in
{
  options.local.docker = {
    enable = lib.mkEnableOption "Docker (manual systemd unit for system-manager hosts)";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.docker ];

    systemd.services.docker = {
      enable = true;
      description = "Docker Application Container Engine";
      documentation = [ "https://docs.docker.com" ];

      wantedBy = [ "multi-user.target" ];

      path = [
        pkgs.docker
        pkgs.iptables
        pkgs.nftables
        pkgs.kmod
        pkgs.containerd
        pkgs.runc
      ];

      serviceConfig = {
        Type = "notify";
        ExecStart = [
          "${pkgs.docker}/bin/dockerd"
        ];
        ExecReload = [
          "${pkgs.coreutils}/bin/kill -s HUP $MAINPID"
        ];

        LimitNOFILE = "1048576";
        LimitNPROC = "infinity";
        LimitCORE = "infinity";
        TasksMax = "infinity";
        TimeoutStartSec = 0;
        Restart = "on-failure";
      };
    };
  };
}
