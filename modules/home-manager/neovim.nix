{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.neovim;
in {
  options.within.neovim.enable = mkEnableOption "Enables Within's Neovim config";

  config = mkIf cfg.enable {
    programs.neovim.enable = true;
    home.file = {
      ".config/nvim" = {
        source = ./nvim;
        recursive = true;
      };
    };
  };
}
