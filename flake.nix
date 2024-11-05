{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
    in {
      nixosConfigurations = {
        razer14 = nixpkgs.lib.nixosSystem {
	  inherit system;
	  specialArgs = {inherit inputs system;};
          modules = [
	    ./hosts/razer14/configuration.nix
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
    };
}
