# parts/nixos.nix
# NixOS system configurations
{ inputs, localLib, ... }:

let
  inherit (localLib)
    systems
    users
    commonSpecialArgs
    mkHomeManagerConfig
    mkUser
    ;

  # Available profiles
  profiles = {
    laptop = ../modules/profiles/laptop.nix;
    desktop = ../modules/profiles/desktop.nix;
    server = ../modules/profiles/server.nix;
    base = ../modules/profiles/base.nix;
  };

  mkNixosConfig =
    {
      system ? systems.linux,
      profile ? "desktop",
      hostConfig,
      username ? users.adriel,
      userConfig ? ../users/adriel,
      extraModules ? [ ],
    }:
    inputs.nixpkgs.lib.nixosSystem {
      inherit system;
      specialArgs = commonSpecialArgs;
      modules = [
        # Profile (base/desktop/laptop/server)
        profiles.${profile}

        # Flake modules
        inputs.solaar.nixosModules.default
        inputs.sops-nix.nixosModules.sops
        inputs.home-manager.nixosModules.home-manager
        mkHomeManagerConfig

        # Host-specific configuration
        hostConfig
        (mkUser username userConfig)
      ]
      ++ extraModules;
    };

in
{
  flake.nixosConfigurations = {
    razer14 = mkNixosConfig {
      profile = "laptop";
      hostConfig = ../hosts/razer14/configuration.nix;
    };

    dell = mkNixosConfig {
      profile = "desktop"; # Has GUI but is a desktop, not laptop
      hostConfig = ../hosts/dell-plex-server/configuration.nix;
    };
  };
}
