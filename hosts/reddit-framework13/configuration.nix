{
  pkgs,
  lib,
  ...
}:

{

  imports = [
    ./../../modules/system-manager/default.nix
  ];
  config = {
    within.kanata = {
      enable = true;
      devices = [
        "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
      ];
    };
    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfree = true;

    users.defaultUserShell = pkgs.zsh;
    users.users."adriel.velazquez".shell = pkgs.zsh;

    environment.systemPackages = [
      pkgs.gparted
      pkgs.nixfmt-rfc-style
      pkgs.docker
      pkgs.apparmor-parser
      pkgs.apparmor-utils
    ];

    systemd.services = {
      docker = {
        enable = true;
        description = "Docker Application Container Engine";
        documentation = [ "https://docs.docker.com" ];
        wantedBy = [ "multi-user.target" ];
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        requires = [ "apparmor.service" ];
        serviceConfig = {
          Type = "notify";
          Environment = [
            "PATH=${
              lib.makeBinPath [
                pkgs.docker
                pkgs.apparmor-parser
                pkgs.apparmor-utils
                pkgs.coreutils
                pkgs.kmod
              ]
            }:/usr/bin:/sbin"
          ];
          ExecStart = "${pkgs.docker}/bin/dockerd";
          ExecStartPost = [
            "${pkgs.coreutils}/bin/chmod 666 /var/run/docker.sock"
            "${pkgs.coreutils}/bin/chown root:docker /var/run/docker.sock"
          ];
          ExecReload = "${pkgs.coreutils}/bin/kill -s HUP $MAINPID";
          TimeoutStartSec = 0;
          RestartSec = 2;
          Restart = "always";
          StartLimitBurst = 3;
          StartLimitInterval = "60s";
          LimitNOFILE = "infinity";
          LimitNPROC = "infinity";
          LimitCORE = "infinity";
          TasksMax = "infinity";
          Delegate = true;
          KillMode = "process";
          OOMScoreAdjust = -500;
        };
      };
    };
  };
}
