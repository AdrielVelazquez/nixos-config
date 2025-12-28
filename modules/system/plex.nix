# modules/system/plex.nix
{ lib, config, ... }:

let
  cfg = config.local.plex;
in
{
  options.local.plex = {
    enable = lib.mkEnableOption "Enables Plex Media Server";

    user = lib.mkOption {
      type = lib.types.str;
      default = "plex";
      description = "User to run Plex as";
      example = "adriel";
    };

    openFirewall = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to open firewall ports for Plex";
    };
  };

  config = lib.mkIf cfg.enable {
    services.plex = {
      enable = true;
      openFirewall = cfg.openFirewall;
      user = cfg.user;
    };
  };
}
