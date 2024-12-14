{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nix-darwin.url = "github:LnL7/nix-darwin";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
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
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in
    {
      nixosConfigurations = {
        razer14 = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs system;
          };
          modules = [
            ./hosts/razer14/configuration.nix
          ];
        };

        dell = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit inputs system;
          };
          modules = [
            ./hosts/dell-plex-server/configuration.nix
          ];
        };
      };
      homeConfigurations = {
        adriel = home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            ./users/adriel.nix
            # inputs.nixvim.homeManagerModules.nixvim
          ];
        };
      };
      darwinConfigurations = {
        PNH46YXX3Y = nix-darwin.lib.darwinSystem {
            modules = [
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
