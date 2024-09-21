{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.neovim;
in {
  options.within.neovim.enable = mkEnableOption "Enables Within's Neovim config";

  config = mkIf cfg.enable {
    home.packages = [ pkgs.neovim ];
    programs.neovim.enable = true;
   };
}
