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
        (pkgs.vimPlugins.nvim-treesitter.withPlugins (p: [
          p.bash
          p.css
          p.dart
          p.dockerfile
          p.go
          p.gomod
          p.gosum
          p.hcl
          p.html
          p.json
          p.lua
          p.luadoc
          p.markdown
          p.markdown_inline
          p.nix
          p.python
          p.regex
          p.rust
          p.terraform
          p.toml
          p.vim
          p.vimdoc
          p.yaml
          p.zig
        ]))
      ];

      extraPackages = with pkgs; [
        # Tree-sitter CLI (grammars provided by withAllGrammars plugin)
        tree-sitter

        # Language servers
        nodejs_24
        vscode-json-languageserver
        markdownlint-cli
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
        zls

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
        flutter
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
