# users/adriel.velazquez.linux.nix
# Work user configuration for adriel.velazquez (Linux systems)
{ pkgs, ... }:

{
  imports = [
    ./common.nix
    ./adriel-modules.nix
  ];

  # ============================================================================
  # User Identity
  # ============================================================================
  home.username = "adriel.velazquez";
  home.homeDirectory = "/home/adriel.velazquez";

  # ============================================================================
  # Nixpkgs
  # ============================================================================
  nixpkgs.config.allowUnfree = true;

  # ============================================================================
  # Environment
  # ============================================================================
  home.sessionVariables = {
    GOPRIVATE = "github.snooguts.net";
  };

  # ============================================================================
  # Git (Work)
  # ============================================================================
  programs.git.settings.url = {
    "git@github.snooguts.net:" = {
      insteadOf = "https://github.snooguts.net/";
    };
  };

  # ============================================================================
  # Additional Packages (work-specific)
  # ============================================================================
  home.packages = with pkgs; [
    # Productivity
    qbittorrent
    bottles
    todoist
    xournalpp
    _1password-gui
    qalculate-qt

    # Development
    openssl
    ed
    docker
    code-cursor
    ollama
    gemini-cli

    # Work tools
    slack
    infrared
    snoologin
    reddit-lint-py
    tilt
    cloudflared
  ];
}
