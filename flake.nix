{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # Nix Cosmic DE stuff
    # nixpkgs.follows = "nixos-cosmic/nixpkgs";
    # nixos-cosmic.url = "github:AdrielVelazquez/nixos-cosmic";
    # nixos-cosmic.url = "github:lilyinstarlight/nixos-cosmic";

    # Nix Darwin (Mac)
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli-wip/nix-homebrew";

    # Optional: Declarative tap management
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
    brew-nix = {
      url = "github:BatteredBunny/brew-nix";
      inputs.nix-darwin.follows = "nix-darwin";
      inputs.brew-api.follows = "brew-api";
      # inputs.flake-utils.follows = "flake-utils";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    brew-api = {
      url = "github:BatteredBunny/brew-api";
      flake = false;
    };
    # ghostty = {
    #   url = "github:ghostty-org/ghostty";
    # };

    # Reddit Specific Packages
    reddit.url = "git+ssh://git@github.snooguts.net/reddit/reddit-nix.git";
    # reddit.url = "git+ssh://git@github.snooguts.net/adriel-velazquez/reddit-nix.git";
    reddit.inputs.nixpkgs.follows = "nixpkgs";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Solaar app
    solaar = {
      url = "https://flakehub.com/f/Svenum/Solaar-Flake/*.tar.gz"; # For latest stable version
      #url = "https://flakehub.com/f/Svenum/Solaar-Flake/0.1.1.tar.gz"; # uncomment line for solaar version 1.1.13
      #url = "github:Svenum/Solaar-Flake/main"; # Uncomment line for latest unstable version
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      reddit,
      nix-homebrew,
      homebrew-cask,
      homebrew-core,
      homebrew-bundle,
      # nixos-cosmic,
      # ghostty,
      solaar,
      ...
    }@inputs:
    let
      mkNixosConfig =
        system: extraModules:
        nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = { inherit inputs system; };
          modules = extraModules;
        };

      mkHmConfig =
        pkgs: extraModules:
        home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = { inherit inputs; };
          modules = extraModules;
        };
    in
    {
      nixosConfigurations = {
        razer14 = mkNixosConfig "x86_64-linux" [
          ./hosts/razer14/configuration.nix
          solaar.nixosModules.default
          # nixos-cosmic.nixosModules.default
        ];
        dell = mkNixosConfig "x86_64-linux" [
          ./hosts/dell-plex-server/configuration.nix
          solaar.nixosModules.default
        ];
      };
      darwinConfigurations = {
        PNH46YXX3Y = nix-darwin.lib.darwinSystem {
          specialArgs = { inherit inputs; };
          modules = [
            {
              nixpkgs.overlays = [
                reddit.overlay
              ];
            }
            ./hosts/reddit-mac/configuration.nix
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                # Install Homebrew under the default prefix
                enable = true;
                autoMigrate = true;

                # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
                enableRosetta = true;

                # User owning the Homebrew prefix
                user = "adriel.velazquez";
                # Optional: Declarative tap management
                taps = {
                  "homebrew/homebrew-core" = homebrew-core;
                  "homebrew/homebrew-cask" = homebrew-cask;
                  "homebrew/homebrew-bundle" = homebrew-bundle;
                };
                # Automatically migrate existing Homebrew installations
                # autoMigrate = true;
              };
            }
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = false;
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs; };
              home-manager.users."adriel.velazquez" = import ./users/adriel.velazquez.nix;
            }
          ];
        };
      };

      homeConfigurations = {
        adriel = mkHmConfig (nixpkgs.legacyPackages."x86_64-linux") [
          ./users/adriel.nix
        ];
      };
    };
}
