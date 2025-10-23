{
  pkgs,
  config,
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
    ];
    systemd.services.docker = {
      enable = true;
      description = "Docker Application Container Engine";
      documentation = [ "https://docs.docker.com" ];
      # wantedBy = [ "multi-user.target" ]; # No longer needed, socket activation handles this
      serviceConfig = {
        Type = "notify";
        # This ExecStart is correct *when paired with the socket below*
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
        SocketGroup = "docker";
      };
    };
    users.groups.docker = { };
    users.users."${config.users.primaryUser.name}".extraGroups = [ "docker" ];
  };
}
