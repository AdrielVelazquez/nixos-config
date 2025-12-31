# NixOS configuration
{ inputs, localLib, ... }:

let
  inherit (localLib) commonSpecialArgs mkHomeManagerConfig mkUser;
in
{
  flake.nixosConfigurations = {
    # Define your host here
    my-laptop = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      specialArgs = commonSpecialArgs;
      modules = [
        # Home Manager integration
        inputs.home-manager.nixosModules.home-manager
        mkHomeManagerConfig

        # Custom modules
        ../modules/system/default.nix

        # Host configuration
        ../hosts/my-laptop/configuration.nix

        # User configuration
        (mkUser "myuser" ../users/myuser/default.nix)
      ];
    };
  };
}

