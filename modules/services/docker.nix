# modules/services/docker.nix
{ lib, config, ... }:

let
  cfg = config.local.docker;
in
{
  options.local.docker = {
    enable = lib.mkEnableOption "Enables Docker";
    autoStart = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether Docker should start automatically at boot.";
    };

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of users with Docker access";
      example = [ "adriel" ];
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker = {
      enable = true;
      enableOnBoot = cfg.autoStart;
    };

    systemd.services.docker.wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);
    systemd.sockets.docker.wantedBy = lib.mkIf (!cfg.autoStart) (lib.mkForce [ ]);

    users.users = lib.genAttrs cfg.users (_userName: {
      extraGroups = [ "docker" ];
    });
  };
}
