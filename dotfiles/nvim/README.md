## Introduction

Native Neovim config managed via Nix. 

## What's Special about using Nix with Neovim

The consistency is the most obvious advantage, but there are some headaches along the way

Dependencies shouldn't be installed via neovim, bul ONLY defined in your nix configuration. 

``` 

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
      pkgs.basedpyright
      # pkgs.pyright
      pkgs.ruff
      pkgs.nixfmt
      pkgs.starlark-rust
      pkgs.zls
      pkgs.ripgrep
      pkgs.ueberzugpp
      pkgs.viu
      pkgs.chafa
    ];
``` 

### FAQ

* Can you really manage neovim with Nix 
* Yes! But you need to commit to the nix philosophy. Anything that want's to install dependencies outside of nix would have a horrible. 

