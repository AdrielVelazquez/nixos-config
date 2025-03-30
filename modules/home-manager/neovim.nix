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
    ];
    programs.neovim.extraPackages = [
      pkgs.nodePackages_latest.vscode-json-languageserver
      pkgs.fzf
      pkgs.lua-language-server
      pkgs.luajitPackages.jsregexp
      pkgs.nil
      pkgs.nixd
      pkgs.go
      pkgs.gopls
      pkgs.gofumpt
      pkgs.stylua
      pkgs.cargo
      pkgs.rustc
      pkgs.basedpyright
      pkgs.terraform-ls
      pkgs.dart
      # pkgs.pyright
      pkgs.ruff
      pkgs.nixfmt-rfc-style
      pkgs.starlark-rust
      pkgs.zls
      pkgs.ripgrep
      pkgs.ueberzugpp
      pkgs.viu
      pkgs.chafa
      pkgs.copilot-node-server
      pkgs.delve
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
