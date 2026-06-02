# parts/lib.nix
{ inputs }:

let
  packageOverlays = {
    asdbctlStudioDisplay = import ../overlays/asdbctl-path-studio-display-1118.nix;
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

  inherit packageOverlays;

  # Home-manager settings shared across NixOS and Darwin
  mkHomeManagerConfig = {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      packageOverlays.asdbctlStudioDisplay
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = { inherit inputs; };
      sharedModules = [
        inputs.sops-nix.homeManagerModules.sops
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
