
# Anything additional that should be added in configuration.nix or hardware-configuration.nix should go here instead.
# This allows faster reproducibility when installing nixos from scratch as both those files can be added into this repo
# And just import the custom-configuration.nix

{
  config,
  pkgs,
  inputs,
  lib,
  ...
}:

{

  imports = [
    # Include the results of the hardware scan.
  ];
      # List packages installed in system profile. To search by name, run:
      # $ nix-env -qaP | grep wget
      nixpkgs.config.allowUnfree = true;
nixpkgs.config.allowUnsupportedSystem = true;
      environment.systemPackages =
        [ pkgs.vim
        ];

      # Necessary for using flakes on this system.
      nix.settings.experimental-features = "nix-command flakes";

      # Enable alternative shell support in nix-darwin.
      # programs.fish.enable = true;

      # Set Git commit hash for darwin-version.
      # system.configurationRevision = self.rev or self.dirtyRev or null;

      # Used for backwards compatibility, please read the changelog before changing.
      # $ darwin-rebuild changelog
      system.stateVersion = 5;

      # The platform the configuration will be used on.
      nixpkgs.hostPlatform = "aarch64-darwin";
      programs.zsh.enable = true;
      users.users."adriel.velazquez" = {
        home = "/Users/adriel.velazquez";
      };
}
