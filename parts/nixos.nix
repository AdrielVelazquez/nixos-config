# parts/nixos.nix
# NixOS system configurations
{ inputs, ... }:

let
  lib = import ./lib.nix { inherit inputs; };
  inherit (lib)
    systems
    users
    commonSpecialArgs
    mkHomeManagerConfig
    mkUser
    ;

  mkNixosConfig =
    {
      system ? systems.linux,
      hostConfig,
      username ? users.adriel,
      userConfig ? ../users/adriel.nix,
      extraModules ? [ ],
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = commonSpecialArgs;
      modules = [
        inputs.solaar.nixosModules.default
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        mkHomeManagerConfig
        hostConfig
        (mkUser username userConfig)
      ]
      ++ extraModules;
    };

in
{
  flake.nixosConfigurations = {
    razer14 = mkNixosConfig {
      hostConfig = ../hosts/razer14/configuration.nix;
    };

    dell = mkNixosConfig {
      hostConfig = ../hosts/dell-plex-server/configuration.nix;
    };
  };
}
