# parts/home-manager.nix
{ inputs, localLib, ... }:

let
  inherit (localLib)
    systems
    commonSpecialArgs
    redditOverlayModule
    packageOverlays
    ;

  mkHomeConfig =
    {
      system ? systems.linux,
      userConfig,
      extraModules ? [ ],
      extraOverlays ? [ ],
    }:
    inputs.home-manager.lib.homeManagerConfiguration {
      pkgs = import inputs.nixpkgs {
        inherit system;
        overlays = [
          inputs.niri.overlays.niri
          packageOverlays.asdbctlStudioDisplay
        ]
        ++ extraOverlays;
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
