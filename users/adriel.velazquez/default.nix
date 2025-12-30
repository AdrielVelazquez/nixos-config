# users/adriel.velazquez/default.nix
# Work user configuration for adriel.velazquez (macOS)
{ pkgs, config, ... }:

{
  imports = [
    ./modules.nix
  ];

  # ============================================================================
  # User Identity
  # ============================================================================
  home.username = "adriel.velazquez";
  home.homeDirectory = "/Users/adriel.velazquez";

  # ============================================================================
  # Home Manager
  # ============================================================================
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
  nixpkgs.config.allowUnfree = true;

  # ============================================================================
  # Environment
  # ============================================================================
  home.sessionVariables = {
    EDITOR = "${pkgs.neovim}/bin/nvim";
  };

  home.sessionPath = [
    "/etc/profiles/per-user/adriel.velazquez/bin/"
    "/opt/reddit/bin/"
    "${config.home.homeDirectory}/go/bin"
  ];

  # ============================================================================
  # Dotfiles
  # ============================================================================
  home.file = {
    ".config/rcm/bindings.conf".text = ''
      .txt = ${pkgs.neovim}/bin/nvim
    '';
  };

  # ============================================================================
  # Packages
  # ============================================================================
  home.packages = with pkgs; [
    # CLI essentials
    vim
    git
    gh
    ripgrep

    # macOS utilities
    rcm
    duti
    watch

    # Development
    go
    google-cloud-sdk
    thrift
    rsync
    awscli2
    graphviz

    # Browsers
    brave
  ];
}
