# modules/system-manager/docker.nix
#
# system-manager doesn't expose `virtualisation.docker`, so we hand-roll the
# systemd unit. Mirrors the small option surface of modules/services/docker.nix
# used by non-NixOS hosts.
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
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether Docker should start automatically at boot instead of on-demand via docker.socket.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.docker ];

    environment.etc."NetworkManager/conf.d/80-unmanaged-docker.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      #
      # Docker owns these interfaces. Leaving them unmanaged prevents
      # NetworkManager consumers from chasing short-lived container veth links.
      [keyfile]
      unmanaged-devices=interface-name:docker0;interface-name:br-*;interface-name:veth*
    '';

    systemd.services.docker = {
      enable = true;
      description = "Docker Application Container Engine";
      documentation = [ "https://docs.docker.com" ];

      requires = [ "docker.socket" ];
      after = [
        "docker.socket"
        "network-online.target"
      ];
      wantedBy = lib.optional cfg.autoStart "multi-user.target";

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
          "${pkgs.docker}/bin/dockerd -H fd://"
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

    systemd.sockets.docker = {
      enable = true;
      description = "Docker Socket for the API";
      wantedBy = [ "sockets.target" ];
      socketConfig = {
        ListenStream = "/run/docker.sock";
        SocketMode = "0660";
        SocketUser = "root";
        SocketGroup = "docker";
        RemoveOnStop = true;
      };
    };
  };
}
