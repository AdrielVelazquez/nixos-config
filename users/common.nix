# users/common.nix
# Shared configuration for all user profiles
{
  pkgs,
  lib,
  config,
  ...
}:

{
  # ============================================================================
  # Home Manager Core Settings
  # ============================================================================
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  # ============================================================================
  # Environment
  # ============================================================================
  home.sessionVariables = {
    EDITOR = "nvim";
  };

  home.sessionPath = [
    "$HOME/go/bin"
  ];

  # ============================================================================
  # Common Packages
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

    # Browsers
    firefox
    brave

    # Utilities
    wl-clipboard
    lshw

    # Nix tools
    nvd # For diffing NixOS generations
  ];

  # ============================================================================
  # Git Configuration
  # ============================================================================
  programs.git = {
    enable = true;
    settings = {
      user.name = lib.mkDefault "Adriel Velazquez";
      init.defaultBranch = "main";
      push.default = "current";
      pull.rebase = false;
    };
  };
}
