# modules/home-manager/discord.nix
{ lib, config, pkgs, ... }:

let
  cfg = config.within.discord;
in
{
  options.within.discord.enable = lib.mkEnableOption "Enables Discord";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.discord ];
  };
}
