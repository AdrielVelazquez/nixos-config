

{ lib, config, pkgs, commands, ... }:

with lib;

let cfg = config.within.steam;
in {
  options.within.steam.enable = mkEnableOption "Enables Steam Settings";

  config = mkIf cfg.enable {
    programs.steam = {
        enable = true;
    };
  };
}

