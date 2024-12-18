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
  };

  outputs =
    {
      self,
      nixpkgs,
      home-manager,
      nix-darwin,
      reddit,
      ...
    }@inputs:
    let
      systems = {
        linux = "x86_64-linux";
        mac = "aarch64-darwin";
      };
      # system = "x86_64-linux";
      # pkgs = nixpkgs.legacyPackages.${system};
      pkgsForSystem =
        system:
        import nixpkgs {
          inherit system;
        };
    in
    {
      nixosConfigurations = {
        razer14 = nixpkgs.lib.nixosSystem {
          system = systems.linux;
          specialArgs = {
            inherit inputs;
          };
          modules = [
            ./hosts/razer14/configuration.nix
          ];
        };

        dell = nixpkgs.lib.nixosSystem {
          system = systems.linux;
          specialArgs = {
            inherit inputs;
          };
          modules = [
            ./hosts/dell-plex-server/configuration.nix
          ];
        };
      };
      homeConfigurations = {
        adriel = home-manager.lib.homeManagerConfiguration {
          pkgs = pkgsForSystem systems.linux;
          modules = [
            ./users/adriel.nix
          ];
        };
      };
      darwinConfigurations = {
        PNH46YXX3Y = nix-darwin.lib.darwinSystem {
          system = systems.mac;
          modules = [
            { nixpkgs.overlays = [ reddit.overlay ]; }
            ./hosts/reddit-mac/configuration.nix
            home-manager.darwinModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users."adriel.velazquez" = import ./users/adriel.velazquez.nix;
            }
          ];
        };
      };
    };
}
