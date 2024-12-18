{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    reddit.url = "git+ssh://git@github.snooguts.net/reddit/reddit-nix.git";
    reddit.inputs.nixpkgs.follows = "nixpkgs";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };

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
    homebrewl-bundle = {
      url = "github:homebrew/homebrew-bundle";
      flake = false;
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
          modules = extraModules;
        };
    in
    {
      nixosConfigurations = {
        razer14 = mkNixosConfig "x86_64-linux" [ ./hosts/razer14/configuration.nix ];
        dell = mkNixosConfig "x86_64-linux" [ ./hosts/dell-plex-server/configuration.nix ];
      };
      darwinConfigurations = {
        PNH46YXX3Y = nix-darwin.lib.darwinSystem {
          modules = [
            { nixpkgs.overlays = [ reddit.overlay ]; }
            ./hosts/reddit-mac/configuration.nix
            nix-homebrew.darwinModules.nix-homebrew
            {
              nix-homebrew = {
                # Install Homebrew under the default prefix
                enable = true;

                # Apple Silicon Only: Also install Homebrew under the default Intel prefix for Rosetta 2
                enableRosetta = true;

                # User owning the Homebrew prefix
                user = "adriel.velazquez";

                # Automatically migrate existing Homebrew installations
                # autoMigrate = true;
              };
            }
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
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
#{
#   description = "Nixos config flake";
#
#   inputs = {
#     nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
#     nix-darwin.url = "github:LnL7/nix-darwin";
#     nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
#     reddit.url = "git+ssh://git@github.snooguts.net/reddit/reddit-nix.git";
#     reddit.inputs.nixpkgs.follows = "nixpkgs";
#     home-manager = {
#       url = "github:nix-community/home-manager/master";
#       inputs.nixpkgs.follows = "nixpkgs";
#     };
#   };
#
#   outputs =
#     {
#       self,
#       nixpkgs,
#       home-manager,
#       nix-darwin,
#       reddit,
#       ...
#     }@inputs:
#     let
#       system = "x86_64-linux";
#       pkgs = nixpkgs.legacyPackages.${system};
#     in
#     {
#       nixosConfigurations = {
#         razer14 = nixpkgs.lib.nixosSystem {
#           inherit system;
#           specialArgs = {
#             inherit inputs system;
#           };
#           modules = [
#             ./hosts/razer14/configuration.nix
#           ];
#         };
#
#         dell = nixpkgs.lib.nixosSystem {
#           inherit system;
#           specialArgs = {
#             inherit inputs system;
#           };
#           modules = [
#             ./hosts/dell-plex-server/configuration.nix
#           ];
#         };
#       };
#       homeConfigurations = {
#         adriel = home-manager.lib.homeManagerConfiguration {
#           inherit pkgs;
#           modules = [
#             ./users/adriel.nix
#             # inputs.nixvim.homeManagerModules.nixvim
#           ];
#         };
#       };
#       darwinConfigurations = {
#         PNH46YXX3Y = nix-darwin.lib.darwinSystem {
#           modules = [
#             { nixpkgs.overlays = [ reddit.overlay ]; }
#             ./hosts/reddit-mac/configuration.nix
#             home-manager.darwinModules.home-manager
#             {
#               home-manager.useGlobalPkgs = true;
#               home-manager.useUserPackages = true;
#               home-manager.users."adriel.velazquez" = import ./users/adriel.velazquez.nix;
#             }
#           ];
#         };
#       };
#     };
# }
