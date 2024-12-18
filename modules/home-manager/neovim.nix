{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.neovim;
in
{
  options.within.neovim.enable = mkEnableOption "Enables Within's Neovim config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.ripgrep
    ];
    programs.neovim.enable = true;
    programs.neovim.viAlias = true;
    programs.neovim.vimAlias = true;
    programs.neovim.vimdiffAlias = true;
    programs.neovim.plugins = [
      pkgs.vimPlugins.nvim-treesitter.withAllGrammars
    ];
    programs.neovim.extraPackages = [
      pkgs.nodePackages_latest.vscode-json-languageserver
      pkgs.lua-language-server
      pkgs.luajitPackages.jsregexp
      pkgs.nil
      pkgs.go
      pkgs.gopls
      pkgs.gofumpt
      pkgs.stylua
      pkgs.cargo
      pkgs.rustc
      pkgs.python3
      # pkgs.pyright
      # pkgs.basedpyright
      pkgs.ruff
      pkgs.nixfmt-rfc-style

    ];
    home.file = {
      ".config/nvim" = {
        source = ./nvim;
        recursive = true;
      };
    };
  };
}
