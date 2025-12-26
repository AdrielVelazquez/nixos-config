# users/adriel.nix
# Personal user configuration for adriel (NixOS systems)
{ pkgs, ... }:

{
  imports = [
    ./common.nix
    ./adriel-modules.nix
  ];

  # ============================================================================
  # User Identity
  # ============================================================================
  home.username = "adriel";
  home.homeDirectory = "/home/adriel";

  # ============================================================================
  # Git
  # ============================================================================
  programs.git.settings = {
    user.email = "AdrielVelazquez@gmail.com";
    url = {
      "git@github.com:" = {
        insteadOf = "https://github.com/";
      };
      "git@github.snooguts.net:" = {
        insteadOf = "https://github.snooguts.net/";
      };
    };
  };

  # ============================================================================
  # Environment
  # ============================================================================
  home.sessionVariables = {
    BROWSER = "firefox";
  };

  # ============================================================================
  # Additional Packages (personal system only)
  # ============================================================================
  home.packages = with pkgs; [
    qbittorrent
    bottles
    todoist
    xournalpp
    _1password-gui
    code-cursor
    popsicle
  ];
}
