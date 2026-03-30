{
  pkgs,
  lib,
  config,
  ...
}:

{

  imports = [
    ./../../modules/system-manager/default.nix
  ];
  config = {
    local.kanata = {
      enable = true;
      devices = [
        "/dev/input/by-path/platform-i8042-serio-0-event-kbd"
      ];
    };

    local.mediatek-wifi.enable = true;

    local.niri.enable = true;

    local.zsa-keyboard.enable = true;

    local.snoocert = {
      enable = true;
      certPath = "/home/adriel/.config/certs/snoodev-ca.crt";
      distro = "arch";
    };

    nixpkgs.hostPlatform = "x86_64-linux";
    nixpkgs.config.allowUnfree = true;

    nix.enable = true;
    nix.settings = {
      experimental-features = [
        "nix-command"
        "flakes"
      ];
      trusted-users = [
        "root"
        "@wheel"
        "adriel"
      ];
    };

    environment.systemPackages = [
      pkgs.zsh
      pkgs.gparted
      pkgs.nixfmt
      pkgs.docker
      pkgs.kitty.terminfo
    ];
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
    environment.etc."systemd/sleep.conf.d/10-suspend-then-hibernate.conf".text = ''
      [Sleep]
      AllowSuspend=yes
      AllowHibernation=yes
      AllowSuspendThenHibernate=yes
      HibernateDelaySec=45min
      HibernateOnACPower=yes
      HibernateMode=shutdown
    '';
    environment.etc."systemd/logind.conf.d/10-lid-switch.conf".text = ''
      [Login]
      HandleLidSwitch=suspend-then-hibernate
      HandleLidSwitchExternalPower=suspend-then-hibernate
      HandleLidSwitchDocked=suspend-then-hibernate
    '';
    # mkForce required to override the hardcoded `true` in system-manager's
    # upstream userborn.nix module. See: https://github.com/numtide/system-manager/issues/350
    services.userborn.enable = lib.mkForce false;
  };
}
