# lib/default.nix
# Shared functions and utilities for the NixOS configuration
{ lib, ... }:

rec {
  # ============================================================================
  # Host Metadata
  # ============================================================================
  hosts = {
    razer14 = {
      hostname = "razer14";
      system = "x86_64-linux";
      timezone = "America/New_York";
      username = "adriel";
      locale = "en_US.UTF-8";
    };
    dell = {
      hostname = "dell-plex";
      system = "x86_64-linux";
      timezone = "America/New_York";
      username = "adriel";
      locale = "en_US.UTF-8";
      roles = [ "plex-server" "ssh-server" ];
    };
    reddit-framework13 = {
      hostname = "reddit-framework13";
      system = "x86_64-linux";
      timezone = "America/New_York";
      username = "adriel.velazquez";
      locale = "en_US.UTF-8";
    };
    reddit-mac = {
      hostname = "PNH46YXX3Y";
      system = "aarch64-darwin";
      timezone = "America/New_York";
      username = "adriel.velazquez";
    };
  };

  # ============================================================================
  # Package Sets
  # ============================================================================
  mkPackageSets = pkgs: {
    # Development tools
    dev = with pkgs; [
      go
      gotools
      gh
      jq
      ripgrep
      nix-prefetch-github
    ];

    # CLI essentials
    cli = with pkgs; [
      vim
      git
      wget
      lshw
    ];

    # Browsers
    browsers = with pkgs; [
      firefox
      brave
    ];

    # Productivity
    productivity = with pkgs; [
      todoist
      xournalpp
      _1password-gui
    ];

    # Media
    media = with pkgs; [
      qbittorrent
    ];

    # Gaming/Entertainment
    gaming = with pkgs; [
      bottles
    ];

    # Reddit-specific tools
    reddit = with pkgs; [
      infrared
      snoologin
      reddit-lint-py
      tilt
      cloudflared
    ];
  };

  # ============================================================================
  # Helper Functions
  # ============================================================================
  
  # Generate locale settings for all LC_* variables
  mkLocaleSettings = locale: lib.genAttrs [
    "LC_ADDRESS"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ] (_: locale);
}

