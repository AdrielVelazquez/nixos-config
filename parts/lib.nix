# parts/lib.nix
{ inputs }:
let
  # Source `codex` from upstream nixpkgs master (freshest release) instead of
  # the pinned main `nixpkgs` fork. See TODO.md for the exception rationale.
  codexOverlay = final: prev: {
    codex = inputs.nixpkgs-master.legacyPackages.${prev.stdenv.hostPlatform.system}.codex;
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

  inherit codexOverlay;

  # Home-manager settings shared across NixOS and Darwin
  mkHomeManagerConfig = {
    nixpkgs.overlays = [
      inputs.niri.overlays.niri
      codexOverlay
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
