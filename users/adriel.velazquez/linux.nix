# users/adriel.velazquez/linux.nix
# Work user configuration for adriel.velazquez (Linux systems)
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
  home.username = "adriel.velazquez";
  home.homeDirectory = "/home/adriel.velazquez";

  # ============================================================================
  # Linux-specific Modules
  # ============================================================================
  local.firefox = {
    enable = true;
    enableVaapi = true;
    useWayland = true;
  };

  # ============================================================================
  # Environment
  # ============================================================================
  home.sessionVariables = {
    EDITOR = "nvim";
    GOPRIVATE = "github.snooguts.net";
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
    kubectl
    openssl
    ed
    docker
    ollama
    gemini-cli

    # Browsers (Firefox managed by local.firefox module)
    brave

    # Utilities
    wl-clipboard
    lshw

    # Communication
    zoom-us
    slack

    # Nix tools
    nvd

    # Productivity
    qbittorrent
    bottles
    todoist
    xournalpp
    _1password-gui
    qalculate-qt
    code-cursor

    # Work tools
    infrared
    snoologin
    reddit-lint-py
    tilt
    cloudflared
  ];

  # ============================================================================
  # Git Configuration
  # ============================================================================
  programs.git = {
    enable = true;
    settings = {
      user.name = "Adriel Velazquez";
      init.defaultBranch = "main";
      push.default = "current";
      pull.rebase = false;
      url = {
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
