# parts/nixos.nix
# NixOS system configurations
{ inputs, ... }:

let
  systems = {
    linux = "x86_64-linux";
    darwin = "aarch64-darwin";
  };

  users = {
    adriel = "adriel";
    adrielVelazquez = "adriel.velazquez";
  };

  commonSpecialArgs = { inherit inputs; };

  mkHomeManagerConfig =
    {
      useGlobalPkgs ? true,
      useUserPackages ? true,
    }:
    {
      home-manager = {
        inherit useGlobalPkgs useUserPackages;
        extraSpecialArgs = commonSpecialArgs;
        sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
      };
    };

  mkUser = username: userConfig: {
    home-manager.users.${username} = import userConfig;
  };

  mkNixosConfig =
    {
      system ? systems.linux,
      hostConfig,
      username ? users.adriel,
      userConfig ? ../users/adriel.nix,
      extraModules ? [ ],
      useGlobalPkgs ? true,
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = commonSpecialArgs;
      modules = [
        inputs.solaar.nixosModules.default
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        (mkHomeManagerConfig { inherit useGlobalPkgs; })
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
