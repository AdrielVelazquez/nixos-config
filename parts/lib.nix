# parts/lib.nix
{ inputs }:

let
  onePasswordMasterOverlay = final: prev: {
    _1password-gui =
      (import inputs.nixpkgs-1password {
        localSystem = final.stdenv.hostPlatform;
        config = prev.config;
      })._1password-gui;
  };
in
{
  systems = {
    linux = "x86_64-linux";
    darwin = "aarch64-darwin";
  };

  users = {
    adriel = "adriel";
    adrielVelazquez = "adriel.velazquez";
  };

  commonSpecialArgs = { inherit inputs; };

  inherit onePasswordMasterOverlay;

  # Home-manager settings shared across NixOS and Darwin
  mkHomeManagerConfig = {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      onePasswordMasterOverlay
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; };
      sharedModules = [
        inputs.sops-nix.homeManagerModules.sops
        inputs.ironbar.homeManagerModules.default
        inputs.walker.homeManagerModules.default
      ];
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
