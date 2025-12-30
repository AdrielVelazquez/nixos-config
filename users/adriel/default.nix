# users/adriel/default.nix
# Personal user configuration for adriel (NixOS systems)
{ pkgs, ... }:

{
  imports = [
    ./modules.nix
  ];

  # ============================================================================
  # Home Manager Core Settings
  # ============================================================================
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  # ============================================================================
  # User Identity
  # ============================================================================
  home.username = "adriel";
  home.homeDirectory = "/home/adriel";

  # ============================================================================
  # Environment
  # ============================================================================
  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "firefox";
    TERMINAL = "kitty";
  };

  home.sessionPath = [
    "$HOME/go/bin"
  ];

  # ============================================================================
  # Packages
  # ============================================================================
  home.packages = with pkgs; [
    # CLI essentials
    jq
    ripgrep
    just

    # Development
    go
    gotools
    gh
    nix-prefetch-github

    # Browsers (Firefox managed by local.firefox module)
    brave

    # Utilities
    wl-clipboard
    lshw

    # Communication
    zoom-us
    discord

    # Nix tools
    nvd

    # Personal
    qbittorrent
    bottles
    todoist
    xournalpp
    _1password-gui
    code-cursor
    popsicle
  ];

  # ============================================================================
  # Git Configuration
  # ============================================================================
  programs.git = {
    enable = true;
    settings = {
      user.name = "Adriel Velazquez";
      user.email = "AdrielVelazquez@gmail.com";
      init.defaultBranch = "main";
      push.default = "current";
      pull.rebase = false;
      url = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
        "git@github.snooguts.net:" = {
          insteadOf = "https://github.snooguts.net/";
        };
      };
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };
}
