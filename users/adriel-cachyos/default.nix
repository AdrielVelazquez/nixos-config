# users/adriel-cachyos/default.nix
# CachyOS Framework 13 user config (work laptop)
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
  programs.niri.enable = true;
  local.niri.enable = true;
  local.niri.useSystemHyprlock = true;
  local.niri.hyprlock.suspendTimeoutSeconds = 600;

  local.zoom = {
    enable = true;
    desktopEnvironment = "niri";
  };

  local.web-mime-defaults.enable = true;

  # Shell & Terminal
  local.zsh.enable = true;
  local.kitty = {
    enable = true;
    enableGpuRecovery = true;
  };
  local.ai-kitten = {
    enable = true;
    cursorCommand = "cursor";
  };

  local.starship.enable = true;

  # Editor
  local.neovim.enable = true;

  # Applications
  local.fonts.enable = true;

  # Security & Secrets
  local.sops.enable = true;
  sops.secrets.cursor_token = { };
  local.ssh.enable = true;
  local.snoocert.enable = true;

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
    GOPRIVATE = "github.snooguts.net";
  };

  home.sessionPath = [
    "$HOME/go/bin"
  ];

  home.packages = (
    with pkgs;
    [
      jq
      ripgrep
      just
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
      wl-clipboard
      lshw
      slack
      nvd
      qbittorrent
      bottles
      todoist
      xournalpp
      kdePackages.okular
      _1password-gui
      qalculate-qt
      code-cursor
      infrared
      snoologin
      reddit-lint-py
      tilt
      cloudflared
      google-cloud-sdk
      tfenv
      obsidian
      brave
      apparmor-utils
      cursor-cli
      codex
      krew
      opencode
      snoodev-system
      peek
      steam
    ]
  );

  local.git.enable = true;

  programs.gh-dash.enable = true;
  programs.obs-studio = {
    enable = true;

    plugins = with pkgs.obs-studio-plugins; [
      wlrobs
      obs-backgroundremoval
      obs-pipewire-audio-capture
      obs-vaapi
      obs-gstreamer
      obs-vkcapture
    ];
  };
}
