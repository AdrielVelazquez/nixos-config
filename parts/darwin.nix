# parts/darwin.nix
# macOS/nix-darwin system configurations
{ inputs, ... }:

let
  systems = {
    linux = "x86_64-linux";
    darwin = "aarch64-darwin";
  };

  users = {
    adriel = "adriel";
    adrielVelazquez = "adriel.velazquez";
  };

  commonSpecialArgs = { inherit inputs; };

  mkHomeManagerConfig = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      extraSpecialArgs = commonSpecialArgs;
      sharedModules = [ inputs.sops-nix.homeManagerModules.sops ];
    };
  };

  mkUser = username: userConfig: {
    home-manager.users.${username} = import userConfig;
  };

  redditOverlayModule = {
    nixpkgs.overlays = [ inputs.reddit.overlay ];
  };

  mkDarwinConfig =
    {
      system ? systems.darwin,
      hostConfig,
      username,
      userConfig,
      extraModules ? [ ],
      homebrewUser ? username,
    }:
    inputs.nix-darwin.lib.darwinSystem {
      inherit system;
      specialArgs = commonSpecialArgs;
      modules = [
        hostConfig
        inputs.nix-homebrew.darwinModules.nix-homebrew
        {
          nix-homebrew = {
            enable = true;
            user = homebrewUser;
            taps = {
              "homebrew/homebrew-core" = inputs.homebrew-core;
              "homebrew/homebrew-cask" = inputs.homebrew-cask;
              "homebrew/homebrew-bundle" = inputs.homebrew-bundle;
            };
          };
        }
        inputs.home-manager.darwinModules.home-manager
        mkHomeManagerConfig
        (mkUser username userConfig)
      ]
      ++ extraModules;
    };

in
{
  flake.darwinConfigurations = {
    PNH46YXX3Y = mkDarwinConfig {
      hostConfig = ../hosts/reddit-mac/configuration.nix;
      username = users.adrielVelazquez;
      userConfig = ../users/adriel.velazquez.nix;
      extraModules = [ redditOverlayModule ];
    };
  };
}
