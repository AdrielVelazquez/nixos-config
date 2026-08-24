{
  description = "Minimal NixOS configuration example";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{
      nixpkgs,
      home-manager,
      ...
    }:
    let
      system = "x86_64-linux";
      specialArgs = { inherit inputs; };
      homeManagerIntegration = {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          extraSpecialArgs = specialArgs;
          backupFileExtension = "hm-backup";
        };
      };
    in
    {
      nixosConfigurations.my-laptop = nixpkgs.lib.nixosSystem {
        inherit system specialArgs;
        modules = [
          home-manager.nixosModules.home-manager
          homeManagerIntegration
          ./modules/system/default.nix
          ./hosts/my-laptop/configuration.nix
          { home-manager.users.myuser = import ./users/myuser; }
        ];
      };

      formatter.${system} = nixpkgs.legacyPackages.${system}.nixfmt-tree;
    };
}
