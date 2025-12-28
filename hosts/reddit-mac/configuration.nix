# hosts/reddit-mac/configuration.nix
# macOS (Darwin) configuration for Reddit work machine
{ pkgs, ... }:

{
  imports = [
    ../../modules/mac-services/default.nix
  ];

  # ============================================================================
  # System
  # ============================================================================
  system.primaryUser = "adriel.velazquez";
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  # ============================================================================
  # Nix Settings
  # ============================================================================
  nix.settings = {
    experimental-features = "nix-command flakes";
    download-buffer-size = 1671088640;
    max-jobs = "auto";
    cores = 0;
  };
  nix.optimise.automatic = true;

  # ============================================================================
  # Nixpkgs
  # ============================================================================
  nixpkgs.config.allowUnfree = true;
  nixpkgs.config.allowUnsupportedSystem = true;

  # ============================================================================
  # Homebrew
  # ============================================================================
  nix-homebrew.autoMigrate = true;

  homebrew = {
    enable = true;
    onActivation.cleanup = "uninstall";

    casks = [
      "firefox"
      "raycast"
      "karabiner-elements"
      "shortwave"
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
  };

  # ============================================================================
  # System Packages
  # ============================================================================
  environment.systemPackages = with pkgs; [
    vim
    git
    go
    duti
    infrared
    reddit-lint-py
    snoodev
    snoologin
  ];

  # ============================================================================
  # Shell
  # ============================================================================
  programs.zsh.enable = true;

  # ============================================================================
  # User
  # ============================================================================
  users.users."adriel.velazquez" = {
    home = "/Users/adriel.velazquez";
  };

  # ============================================================================
  # Module Options
  # ============================================================================
  local.kanata.enable = true;
}
