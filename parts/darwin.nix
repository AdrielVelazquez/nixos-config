# parts/darwin.nix
{ inputs, localLib, ... }:

let
  inherit (localLib)
    systems
    users
    commonSpecialArgs
    mkHomeManagerConfig
    mkUser
    redditOverlayModule
    ;

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
      userConfig = ../users/adriel.velazquez;
      extraModules = [ redditOverlayModule ];
    };
  };
}
