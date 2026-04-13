# modules/home-manager/neovim.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.neovim;

  treeSitterGrammars = [
    pkgs.tree-sitter.builtGrammars."tree-sitter-bash"
    pkgs.tree-sitter.builtGrammars."tree-sitter-css"
    pkgs.tree-sitter.builtGrammars."tree-sitter-dart"
    pkgs.tree-sitter.builtGrammars."tree-sitter-dockerfile"
    pkgs.tree-sitter.builtGrammars."tree-sitter-go"
    pkgs.tree-sitter.builtGrammars."tree-sitter-gomod"
    pkgs.tree-sitter.builtGrammars."tree-sitter-hcl"
    pkgs.tree-sitter.builtGrammars."tree-sitter-html"
    pkgs.tree-sitter.builtGrammars."tree-sitter-json"
    pkgs.tree-sitter.builtGrammars."tree-sitter-lua"
    pkgs.tree-sitter.builtGrammars."tree-sitter-markdown"
    pkgs.tree-sitter.builtGrammars."tree-sitter-markdown-inline"
    pkgs.tree-sitter.builtGrammars."tree-sitter-nix"
    pkgs.tree-sitter.builtGrammars."tree-sitter-python"
    pkgs.tree-sitter.builtGrammars."tree-sitter-regex"
    pkgs.tree-sitter.builtGrammars."tree-sitter-rust"
    pkgs.tree-sitter.builtGrammars."tree-sitter-toml"
    pkgs.tree-sitter.builtGrammars."tree-sitter-vim"
    pkgs.tree-sitter.builtGrammars."tree-sitter-yaml"
    pkgs.tree-sitter.builtGrammars."tree-sitter-zig"
  ];

  treeSitterParsers = pkgs.tree-sitter.withPlugins (_: treeSitterGrammars);

  treeSitterQueries = pkgs.runCommandLocal "nvim-treesitter-queries" { } ''
    mkdir -p "$out"

    ${lib.concatMapStringsSep "\n" (
      grammar:
      let
        lang = lib.replaceStrings [ "-" ] [ "_" ] (lib.removePrefix "tree-sitter-" (lib.getName grammar));
      in
      ''
        if [ -d "${grammar}/queries" ]; then
          ln -s "${grammar}/queries" "$out/${lang}"
        fi
      ''
    ) treeSitterGrammars}
  '';
in
{
  options.local.neovim.enable = lib.mkEnableOption "Enables Neovim configuration";

  config = lib.mkIf cfg.enable {
    programs.neovim = {
      enable = true;
      viAlias = true;
      vimAlias = true;
      vimdiffAlias = true;
      withRuby = false;
      withPython3 = false;

      extraPackages = with pkgs; [
        # Tree-sitter CLI (parsers are exposed via ~/.local/share/nvim/site/parser)
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

    home.file.".local/share/nvim/site/parser".source = treeSitterParsers;
    home.file.".local/share/nvim/site/queries".source = treeSitterQueries;

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
