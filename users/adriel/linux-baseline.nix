{ pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/default.nix
    ../../modules/home-manager/ai-kitten.nix
  ];

  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
  home.username = "adriel";
  home.homeDirectory = "/home/adriel";

  local.zsh.enable = true;
  local.kitty.enable = true;
  local.starship.enable = true;
  local.neovim.enable = true;
  local.antigravity-cli.enable = true;
  local.codex-cli.enable = true;
  local.gemini-cli.enable = true;
  local.opencode.enable = true;
  local.headroom.enable = true;
  local.ai-kitten.enable = true;
  local.fonts.enable = true;
  local.sops.enable = true;
  local.ssh.enable = true;
  local.git.enable = true;
  local.web-mime-defaults.enable = true;
  local.zen-domain-tab-grouper.enable = true;

  local.zen-browser = {
    enable = true;
    enableVaapi = true;
    useWayland = true;
  };

  local.vivaldi = {
    enable = true;
    enableVaapi = true;
    useWayland = true;
  };

  home.sessionVariables = {
    EDITOR = "nvim";
    HEADROOM_MODE = "token";
    HEADROOM_INTERCEPT_ENABLED = "1";
  };

  home.sessionPath = [
    "$HOME/go/bin"
  ];

  home.packages = with pkgs; [
    jq
    ripgrep
    just
    go
    gotools
    gh
    nix-prefetch-github
    kubectl
    wl-clipboard
    lshw
    nvd
    qbittorrent
    todoist
    xournalpp
    kdePackages.okular
    haruna
    _1password-gui
    obsidian
  ];
}
