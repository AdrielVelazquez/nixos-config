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
  # macOS System Defaults
  # ============================================================================
  system.defaults = {
    # Dock
    dock = {
      autohide = true;
      autohide-delay = 0.0;
      autohide-time-modifier = 0.4;
      mru-spaces = false; # Don't rearrange spaces based on recent use
      show-recents = false;
      tilesize = 48;
    };

    # Finder
    finder = {
      AppleShowAllExtensions = true;
      AppleShowAllFiles = false;
      ShowPathbar = true;
      ShowStatusBar = true;
      FXPreferredViewStyle = "Nlsv"; # List view
      FXEnableExtensionChangeWarning = false;
    };

    # Keyboard
    NSGlobalDomain = {
      AppleKeyboardUIMode = 3; # Full keyboard navigation
      KeyRepeat = 2; # Fast key repeat
      InitialKeyRepeat = 15; # Short delay before repeat
      ApplePressAndHoldEnabled = false; # Disable press-and-hold for accents
      NSAutomaticCapitalizationEnabled = false;
      NSAutomaticDashSubstitutionEnabled = false;
      NSAutomaticPeriodSubstitutionEnabled = false;
      NSAutomaticQuoteSubstitutionEnabled = false;
      NSAutomaticSpellingCorrectionEnabled = false;
    };

    # Trackpad
    trackpad = {
      Clicking = true; # Tap to click
      TrackpadRightClick = true;
      TrackpadThreeFingerDrag = true;
    };

    # Login window
    loginwindow = {
      GuestEnabled = false;
    };

    # Screenshots
    screencapture = {
      location = "~/Pictures/Screenshots";
      type = "png";
    };
  };

  # ============================================================================
  # Nix Settings
  # ============================================================================
  nix.settings = {
    experimental-features = "nix-command flakes";
    download-buffer-size = 1671088640;
    max-jobs = "auto";
  };
  nix.optimise.automatic = true;

  # ============================================================================
  # Nixpkgs
  # ============================================================================
  nixpkgs.config.allowUnfree = true;

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
      # Keep these in Homebrew (not well-maintained in nixpkgs or need taps)
      "sourcegraph/src-cli/src-cli"
      "tfenv"
      "grpc"
      "reddit/reddit/reddit-brew-scripts"
    ];
  };

  # ============================================================================
  # System Packages
  # ============================================================================
  environment.systemPackages = with pkgs; [
    # Core tools
    vim
    git
    go
    wget
    rsync

    # Build tools (moved from Homebrew)
    autoconf
    automake
    libtool

    # macOS utilities
    duti

    # Reddit tools
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
  # Karabiner-Elements for keyboard remapping (Colemak-DH + home row mods)
  # Replaces kanata - better macOS integration, auto-starts, per-app support
  local.karabiner.enable = true;
}
