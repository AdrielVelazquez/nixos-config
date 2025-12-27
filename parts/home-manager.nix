# parts/home-manager.nix
# Standalone home-manager configurations (for non-NixOS systems)
{ inputs, ... }:

let
  systems = {
    linux = "x86_64-linux";
    darwin = "aarch64-darwin";
  };

  commonSpecialArgs = { inherit inputs; };

  redditOverlayModule = {
    nixpkgs.overlays = [ inputs.reddit.overlay ];
  };

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
      ]
      ++ extraModules
      ++ [ userConfig ];
    };

in
{
  flake.homeConfigurations = {
    adriel = mkHomeConfig {
      userConfig = ../users/adriel.nix;
    };

    reddit-framework13 = mkHomeConfig {
      userConfig = ../users/adriel.velazquez.linux.nix;
      extraModules = [ redditOverlayModule ];
    };
  };
}
