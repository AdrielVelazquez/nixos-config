

{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.docker;
in {
  options.within.docker.enable = mkEnableOption "Enables docker Settings";
  options.within.docker.users = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "List of users with Docker access.";
      example = [ "user1" "user2" ];
    };
  config = mkIf cfg.enable {
    virtualisation.docker.enable = true;
    users.users = genAttrs cfg.users (userName: {
      extraGroups = [ "docker" ];
    });
  };
}

