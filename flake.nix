{
  description = "Nixos config flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixvim = {
        url = "github:nix-community/nixvim";
        # If you are not running an unstable channel of nixpkgs, select the corresponding branch of nixvim.
        # url = "github:nix-community/nixvim/nixos-24.05";

        inputs.nixpkgs.follows = "nixpkgs";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
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
        inputs.nixvim.homeManagerModules.nixvim
      ];
	};
     };
    };
}
