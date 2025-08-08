# ~/.nixos/flake.nix
{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------------
    # ## Secrets ##
    # --------------------------------------------------------------------------------
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------------
    # ## Applications ##
    # --------------------------------------------------------------------------------
    solaar = {
      url = "github:Svenum/Solaar-Flake";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------------
    # ## Reddit Specific ##
    # --------------------------------------------------------------------------------
    reddit = {
      url = "git+ssh://git@github.snooguts.net/reddit/reddit-nix.git";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    fleet-nix = {
      url = "github:AdrielVelazquez/fleet-nixos";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # --------------------------------------------------------------------------------
    # ## macOS Specific ##
    # --------------------------------------------------------------------------------
    nix-darwin = {
      url = "github:LnL7/nix-darwin";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-homebrew = {
      url = "github:zhaofengli-wip/nix-homebrew";
    };
    homebrew-core = {
      url = "github:homebrew/homebrew-core";
      flake = false;
    };
    homebrew-cask = {
      url = "github:homebrew/homebrew-cask";
      flake = false;
    };
    homebrew-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
    };
  };

  # --------------------------------------------------------------------------------
  outputs =
    { self, ... }@inputs:
    let
      mkNixosConfig =
        system: useGlobalPkgsValue: hostSpecificModules:
        inputs.nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs; };
          modules = [
            # Common modules for all hosts
            inputs.solaar.nixosModules.default
            inputs.sops-nix.nixosModules.sops
            inputs.home-manager.nixosModules.home-manager
            {
              # Inject the host-specific value here
              home-manager.useGlobalPkgs = useGlobalPkgsValue;

              # Other common home-manager settings
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users.adriel = import ./users/adriel.nix;
            }
          ] ++ hostSpecificModules; # Append host-unique modules
        };
    in
    {
      nixosConfigurations = {
        razer14 = mkNixosConfig "x86_64-linux" true [
          ./hosts/razer14/configuration.nix
        ];

        dell = mkNixosConfig "x86_64-linux" true [
          ./hosts/dell-plex-server/configuration.nix
        ];

        reddit-framework13 = mkNixosConfig "x86_64-linux" true [
          ./hosts/reddit-framework13/configuration.nix
          { nixpkgs.overlays = [ inputs.reddit.overlay ]; }
        ];
      };

      darwinConfigurations = {
        PNH46YXX3Y = inputs.nix-darwin.lib.darwinSystem {
          system = "aarch64-darwin";
          specialArgs = { inherit inputs; };
          modules = [
            ./hosts/reddit-mac/configuration.nix
            inputs.nix-homebrew.darwinModules.nix-homebrew
            {
              nixpkgs.overlays = [ inputs.reddit.overlay ];
              nix-homebrew = {
                enable = true;
                user = "adriel.velazquez";
                taps = {
                  "homebrew/homebrew-core" = inputs.homebrew-core;
                  "homebrew/homebrew-cask" = inputs.homebrew-cask;
                  "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
                };
              };
            }
            inputs.home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users."adriel.velazquez" = import ./users/adriel.velazquez.nix;
            }
          ];
        };
      };

      homeConfigurations.adriel = inputs.home-manager.lib.homeManagerConfiguration {
        pkgs = inputs.nixpkgs.legacyPackages."x86_64-linux";
        extraSpecialArgs = { inherit inputs; };
        modules = [ ./users/adriel.nix ];
      };
    };
}
