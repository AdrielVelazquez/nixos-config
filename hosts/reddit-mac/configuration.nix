# Anything additional that should be added in configuration.nix or hardware-configuration.nix should go here instead.
# This allows faster reproducibility when installing nixos from scratch as both those files can be added into this repo
# And just import the custom-configuration.nix

{
  pkgs,
  inputs,
  ...
}:

{

  imports = [
    # Include the results of the hardware scan.
    ./../../modules/mac-services/default.nix
  ];
  # List packages installed in system profile. To search by name, run:
  # $ nix-env -qaP | grep wget
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;
  nixpkgs = {
    overlays = [
      inputs.brew-nix.overlays.default
    ];
  };
  system.primaryUser = "adriel.velazquez";
  nix.settings.download-buffer-size = 1671088640;
  # nix.settings.auto-optimise-store = true;
  nix.optimise.automatic = true;
  homebrew = {
    enable = true;
    casks = [
      "firefox"
      "raycast"
      "karabiner-elements"
      "readdle-spark"
      "adobe-acrobat-reader"
    ];

    brews = [
      "kanata"
      "wget"
      "sourcegraph/src-cli/src-cli"
      "tfenv"
      "grpc"
      "autoconf"
      "automake"
      "libtool"
      "shtool"
      "reddit/reddit/reddit-brew-scripts"
      "rsync"
    ];
    onActivation.cleanup = "uninstall";
  };

  environment.systemPackages = [
    pkgs.vim
    pkgs.infrared
    pkgs.reddit-lint-py
    pkgs.snoodev
    pkgs.snoologin
    # pkgs.snootobuf
    pkgs.duti
    pkgs.go
    pkgs.git

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
  # pkgs.hostPlatform = "aarch64-darwin";
  programs.zsh.enable = true;
  users.users."adriel.velazquez" = {
    home = "/Users/adriel.velazquez";
  };
  within.kanata.enable = true;
}
