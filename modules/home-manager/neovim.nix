# modules/home-manager/neovim.nix
# Neovim configuration
{ lib, config, pkgs, ... }:

let
  cfg = config.within.neovim;
in
{
  options.within.neovim.enable = lib.mkEnableOption "Enables Neovim configuration";

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins = [
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars
        pkgs.vimPlugins.nvim-treesitter
      ];

      extraPackages = with pkgs; [
        # Tree-sitter
        tree-sitter
        lua54Packages.jsregexp
        tree-sitter-grammars.tree-sitter-lua
        tree-sitter-grammars.tree-sitter-nix
        tree-sitter-grammars.tree-sitter-go
        tree-sitter-grammars.tree-sitter-python
        tree-sitter-grammars.tree-sitter-bash
        tree-sitter-grammars.tree-sitter-regex
        tree-sitter-grammars.tree-sitter-markdown
        tree-sitter-grammars.tree-sitter-json

        # Language servers
        nodejs_24
        nodePackages_latest.vscode-json-languageserver
        lua-language-server
        luajitPackages.jsregexp
        nixd
        gopls
        basedpyright
        terraform-ls
        terraform-lsp
        pyrefly
        ruff
        zls

        # Formatters
        gofumpt
        stylua
        nixfmt-rfc-style

        # Tools
        fzf
        go
        cargo
        rustc
        dart
        starlark-rust
        ripgrep
        delve

        # Image support
        ueberzugpp
        viu
        chafa
        imagemagick
      ];
    };

    home.file.".config/nvim" = {
      source = ../../dotfiles/nvim;
      recursive = true;
    };

    # Desktop entry (Linux only)
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
