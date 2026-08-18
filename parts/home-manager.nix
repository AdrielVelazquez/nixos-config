# parts/home-manager.nix
{ inputs, localLib, ... }:

let
  inherit (localLib)
    systems
    commonSpecialArgs
    redditOverlayModule
    ;

  mkHomeConfig =
    {
      system ? systems.linux,
      userConfig,
      extraModules ? [ ],
      extraOverlays ? [ ],
      extraNixpkgsConfig ? { },
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = extraOverlays;
        config = {
          allowUnfree = true;
        }
        // extraNixpkgsConfig;
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
    razer14 = mkHomeConfig {
      userConfig = ../users/adriel;
      extraNixpkgsConfig.cudaCapabilities = [ "12.0" ];
    };

    cachyos-framework13 = mkHomeConfig {
      userConfig = ../users/adriel-cachyos;
      extraModules = [ redditOverlayModule ];
    };
  };
}
