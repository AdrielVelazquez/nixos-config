{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.neovim;
in {
  options.within.neovim.enable = mkEnableOption "Enables Within's Neovim config";

  config = mkIf cfg.enable {
    home.packages = [
        pkgs.nix-ld
        pkgs.ripgrep
    ];
    programs.neovim.enable = true;
    programs.neovim.viAlias = true;
    programs.neovim.vimAlias = true;
    programs.neovim.vimdiffAlias = true;
    programs.neovim.extraPackages = [
        pkgs.nodePackages_latest.vscode-json-languageserver
    ];
    home.file = {
      ".config/nvim" = {
        source = ./nvim;
        recursive = true;
      };
    };
  };
}
