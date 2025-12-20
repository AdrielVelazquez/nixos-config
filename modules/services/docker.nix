# modules/services/docker.nix
{ lib, config, ... }:

let
  cfg = config.within.docker;
in
{
  options.within.docker = {
    enable = lib.mkEnableOption "Enables Docker";

    users = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "List of users with Docker access";
      example = [ "adriel" ];
    };
  };

  config = lib.mkIf cfg.enable {
    virtualisation.docker.enable = true;

    users.users = lib.genAttrs cfg.users (_userName: {
      extraGroups = [ "docker" ];
    });
  };
}
