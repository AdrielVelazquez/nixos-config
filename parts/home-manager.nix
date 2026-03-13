# parts/home-manager.nix
{ inputs, localLib, ... }:

let
  inherit (localLib) systems commonSpecialArgs redditOverlayModule;

  mkHomeConfig =
    {
      system ? systems.linux,
      userConfig,
      extraModules ? [ ],
      overlays ? [ ],
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system overlays;
        config.allowUnfree = true;
      };
      extraSpecialArgs = commonSpecialArgs;
      modules = [
        inputs.sops-nix.homeManagerModules.sops
        inputs.niri.homeModules.niri
      ]
      ++ extraModules
      ++ [ userConfig ];
    };

in
{
  flake.homeConfigurations = {
    adriel = mkHomeConfig {
      userConfig = ../users/adriel;
    };

    cachyos-framework13 = mkHomeConfig {
      userConfig = ../users/adriel-cachyos;
      extraModules = [ redditOverlayModule ];
    };
  };
}
