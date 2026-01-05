# hosts/reddit-mac/configuration.nix
{ pkgs, ... }:

{
  imports = [
    ../../modules/mac-services/default.nix
  ];

  system.primaryUser = "adriel.velazquez";
  system.stateVersion = 5;
  nixpkgs.hostPlatform = "aarch64-darwin";

  system.defaults = {
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.4;
      mru-spaces = false;
      show-recents = false;
      tilesize = 48;
    };

    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "Nlsv";
      FXEnableExtensionChangeWarning = false;
    };

    NSGlobalDomain = {
      AppleKeyboardUIMode = 3;
      KeyRepeat = 2;
      InitialKeyRepeat = 15;
      ApplePressAndHoldEnabled = false;
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };

    trackpad = {
      Clicking = true;
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

    loginwindow = {
      GuestEnabled = false;
    };

    screencapture = {
      location = "~/Pictures/Screenshots";
      type = "png";
    };
  };

  nix.settings = {
    experimental-features = "nix-command flakes";
    download-buffer-size = 1671088640;
    max-jobs = "auto";
  };
  nix.optimise.automatic = true;

  nixpkgs.config.allowUnfree = true;

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
      "sourcegraph/src-cli/src-cli"
      "tfenv"
      "grpc"
      "reddit/reddit/reddit-brew-scripts"
    ];
  };

  environment.systemPackages = with pkgs; [
    vim
    git
    go
    wget
    rsync
    autoconf
    automake
    libtool
    duti
    infrared
    reddit-lint-py
    snoodev
    snoologin
  ];

  programs.zsh.enable = true;

  users.users."adriel.velazquez" = {
    home = "/Users/adriel.velazquez";
  };

  local.karabiner.enable = true;
}
