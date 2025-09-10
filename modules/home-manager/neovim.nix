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
    programs.neovim.enable = true;
    programs.neovim.viAlias = true;
    programs.neovim.vimAlias = true;
    programs.neovim.vimdiffAlias = true;
    programs.neovim.plugins = [
      pkgs.vimPlugins.nvim-treesitter.withAllGrammars
      pkgs.vimPlugins.nvim-treesitter
    ];
    programs.neovim.extraPackages = [
      pkgs.tree-sitter
      pkgs.lua54Packages.jsregexp
      pkgs.tree-sitter-grammars.tree-sitter-lua
      pkgs.tree-sitter-grammars.tree-sitter-nix
      pkgs.tree-sitter-grammars.tree-sitter-go
      pkgs.tree-sitter-grammars.tree-sitter-python
      pkgs.tree-sitter-grammars.tree-sitter-bash
      pkgs.tree-sitter-grammars.tree-sitter-regex
      pkgs.tree-sitter-grammars.tree-sitter-markdown
      pkgs.tree-sitter-grammars.tree-sitter-json

      pkgs.nodejs_24
      pkgs.nodePackages_latest.vscode-json-languageserver
      pkgs.fzf
      pkgs.lua-language-server
      pkgs.luajitPackages.jsregexp
      pkgs.nixd
      pkgs.go
      pkgs.gopls
      pkgs.gofumpt
      pkgs.stylua
      pkgs.cargo
      pkgs.rustc
      pkgs.basedpyright
      pkgs.terraform-ls
      pkgs.terraform-lsp
      pkgs.dart
      pkgs.pyrefly
      pkgs.ruff
      pkgs.nixfmt-rfc-style
      pkgs.starlark-rust
      pkgs.zls
      pkgs.ripgrep
      pkgs.ueberzugpp
      pkgs.viu
      pkgs.chafa
      pkgs.delve
      pkgs.imagemagick
    ];
    home.file = {
      ".config/nvim" = {
        source = ../../dotfiles/nvim;
        recursive = true;
      };
    };
    # Conditionally add xdg.desktopEntries for Linux
    xdg.desktopEntries = lib.optionalAttrs pkgs.stdenv.isLinux {
      neovim = {
        name = "Neovim";
        genericName = "editor";
        exec = "nvim -f %F";
        mimeType = [
          "text/html"
          "text/xml"
          "text/plain"
          "text/english"
          "text/x-makefile"
          "text/x-c++hdr"
          "text/x-tex"
          "application/x-shellscript"
        ];
        terminal = false;
        type = "Application";
      };
    };
  };
}
