# parts/checks.nix
{ config, localLib, ... }:

let
  inherit (localLib) systems;

in
{
  flake.checks = {
    ${systems.linux} = {
      # NixOS configuration checks
      razer14 = config.flake.nixosConfigurations.razer14.config.system.build.toplevel;
      dell = config.flake.nixosConfigurations.dell.config.system.build.toplevel;

      # Home Manager configuration checks
      home-adriel = config.flake.homeConfigurations.adriel.activationPackage;
      home-cachyos-framework13 = config.flake.homeConfigurations.cachyos-framework13.activationPackage;

      # system-manager configuration check
      system-cachyos-framework = config.flake.systemConfigs.cachyos-framework;
    };
    ${systems.darwin} = {
      # Darwin configuration check
      reddit-mac = config.flake.darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel;
    };
  };

  perSystem =
    { pkgs, ... }:
    let
      src = ../.;
    in
    {
      checks = {
        nix-format =
          pkgs.runCommand "nix-format-check"
            {
              nativeBuildInputs = [
                pkgs.findutils
                pkgs.nixfmt
              ];
            }
            ''
              find "${src}" -type f -name '*.nix' -print0 \
                | xargs -0 -r nixfmt --check
              touch "$out"
            '';

        lua-format =
          pkgs.runCommand "lua-format-check"
            {
              nativeBuildInputs = [
                pkgs.findutils
                pkgs.stylua
              ];
            }
            ''
              find "${src}" -type f -name '*.lua' -print0 \
                | xargs -0 -r stylua --check \
                    --config-path "${src}/dotfiles/nvim/.stylua.toml"
              touch "$out"
            '';

        nvim-regressions =
          pkgs.runCommand "nvim-regressions"
            {
              nativeBuildInputs = [ pkgs.neovim ];
            }
            ''
              export HOME="$TMPDIR"
              cd "${src}"
              nvim --headless -u NONE -i NONE --noplugin -l tests/nvim/conform-json.lua
              nvim --headless -u NONE -i NONE --noplugin -l tests/nvim/snacks-dashboard.lua
              touch "$out"
            '';

        shell-syntax =
          pkgs.runCommand "shell-syntax-check"
            {
              nativeBuildInputs = [
                pkgs.bash
                pkgs.findutils
              ];
            }
            ''
              while IFS= read -r -d "" script; do
                bash -n "$script"
              done < <(find "${src}" -type f -name '*.sh' -print0)
              touch "$out"
            '';
      };
    };
}
