
{ lib, config, pkgs, ... }:

with lib;

let cfg = config.within.nixvim;
in {
  options.within.nixvim.enable = mkEnableOption "Enables Within's Neovim with NixVim config";

  config = mkIf cfg.enable {
    # home.packages = [
    #     pkgs.nixvim
    #     pkgs.ripgrep
    # ];
    # programs.neovim.enable = true;
    # programs.neovim.viAlias = true;
    # programs.neovim.vimAlias = true;
    # programs.neovim.vimdiffAlias = true;
    # programs.neovim.extraPackages = [
    #     pkgs.nodePackages_latest.vscode-json-languageserver
    # ];
    # home.file = {
    #   ".config/nvim" = {
    #     source = ./nvim;
    #     recursive = true;
    #   };
    programs.nixvim = {
        enable = true;

        colorschemes.catppuccin.enable = true;
        plugins.lualine.enable = true;
        plugins.telescope.enable = true;	
    };

    programs.nixvim.opts = {
	relativenumber = true;
	tabstop = 4;
	expandtab = true;
	softtabstop = 4;
	shiftwidth = 4;
	smartindent = true;	
    };
    };
  }
