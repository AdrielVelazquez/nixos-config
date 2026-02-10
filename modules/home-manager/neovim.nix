# modules/home-manager/neovim.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.neovim;
in
{
  options.local.neovim.enable = lib.mkEnableOption "Enables Neovim configuration";

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;

      plugins = [
        pkgs.vimPlugins.nvim-treesitter.withAllGrammars
      ];

      extraPackages = with pkgs; [
        # Tree-sitter CLI (grammars provided by withAllGrammars plugin)
        tree-sitter

        # Language servers
        nodejs_24
        nodePackages_latest.vscode-json-languageserver
        nodePackages.markdownlint-cli
        lua-language-server
        luajitPackages.jsregexp # Required for LuaSnip regex transforms
        nixd
        gopls
        basedpyright
        marksman
        terraform-ls
        terraform-lsp
        pyrefly
        ruff
        # re-enable zls when upstream is fixed. Also disabling in nvim config
        # zls

        # Formatters
        gofumpt
        stylua
        nixfmt

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
