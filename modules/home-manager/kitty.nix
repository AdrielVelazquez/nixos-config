{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.kitty;
in {
  options.within.kitty.enable = mkEnableOption "Enables Within's vim config";

  config = mkIf cfg.enable {
    home.packages = [ pkgs.kitty ];
    programs.kitty.enable = true;
    programs.kitty.shellIntegration.enableZshIntegration = true;
   };
}
