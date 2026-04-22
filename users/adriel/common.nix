# users/adriel/common.nix
#
# Shared HM config for the personal `adriel` user across hosts.
# Anything host-specific (e.g. razer14's niri DRM device paths) belongs in
# the per-host wrapper (users/adriel/default.nix, users/adriel-dell/default.nix, ...).
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
  local.gemini-cli.enable = true;
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
  local.fonts.enable = true;
  local.sops.enable = true;
  sops.secrets.cursor_token = { };
  local.ssh.enable = true;

  local.git = {
    enable = true;
    userEmail = "AdrielVelazquez@gmail.com";
    extraInsteadOf = {
      "git@github.com:" = {
        insteadOf = "https://github.com/";
      };
    };
  };

  local.ai-kitten = {
    enable = true;
    cursorCommand = "cursor-agent";
  };

  local.web-mime-defaults.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "zen-browser";
    TERMINAL = "kitty";
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
    zoom-us
    discord
    nvd
    qbittorrent
    bottles
    todoist
    xournalpp
    kdePackages.okular
    _1password-gui
    code-cursor
    popsicle
    obsidian
    opencode
    cursor-cli
    codex
    (llama-cpp.override { cudaSupport = true; })
  ];

  services.gnome-keyring.enable = true;

  home.file.".config/opencode" = {
    source = ../../dotfiles/opencode;
    recursive = true;
  };
}
