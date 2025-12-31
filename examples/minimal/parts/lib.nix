# Shared utilities and constants
{ inputs }:

{
  # Common special args passed to all modules
  commonSpecialArgs = { inherit inputs; };

  # Home Manager configuration for NixOS integration
  mkHomeManagerConfig = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; };
      backupFileExtension = "hm-backup";
    };
  };

  # Create a home-manager user module
  mkUser = username: userConfig: {
    home-manager.users.${username} = import userConfig;
  };
}
