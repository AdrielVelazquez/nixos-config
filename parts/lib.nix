# parts/lib.nix
# Shared constants and utilities for flake parts
{ inputs }:

{
  # ============================================================================
  # Constants
  # ============================================================================
  systems = {
    linux = "x86_64-linux";
    darwin = "aarch64-darwin";
  };

  users = {
    adriel = "adriel";
    adrielVelazquez = "adriel.velazquez";
  };

  # ============================================================================
  # Common Configuration
  # ============================================================================
  commonSpecialArgs = { inherit inputs; };

  # Home-manager settings shared across NixOS and Darwin
  mkHomeManagerConfig = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; };
      sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
      # Back up existing files instead of failing
      backupFileExtension = "hm-backup";
    };
  };

  # Create a home-manager user configuration module
  mkUser = username: userConfig: {
    home-manager.users.${username} = import userConfig;
  };

  # Reddit nixpkgs overlay module
  redditOverlayModule = {
    nixpkgs.overlays = [ inputs.reddit.overlay ];
  };
}
