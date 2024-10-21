
{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.cuda;
in {
  options.within.cuda.enable = mkEnableOption "Enables cuda `Settings";

  config = mkIf cfg.enable {
   environment.systemPackages = with pkgs; [
      cudatoolkit
    ];
  };
}
