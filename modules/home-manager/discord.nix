# modules/home-manager/discord.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.discord;
in
{
  options.local.discord.enable = lib.mkEnableOption "Enables Discord";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.discord ];
  };
}
