# users/adriel-cachyos/default.nix
# CachyOS Framework 13 user config (work laptop)
{ pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/default.nix
  ];

  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
  home.username = "adriel";
  home.homeDirectory = "/home/adriel";
  local.niri.enable = true;

  # Shell & Terminal
  local.zsh.enable = true;
  local.kitty = {
    enable = true;
    enableGpuRecovery = true;
  };
  local.starship.enable = true;

  # Editor
  local.neovim.enable = true;

  # Applications
  local.fonts.enable = true;

  # Security & Secrets
  local.sops.enable = true;
  local.ssh.enable = true;
  local.snoocert = {
    enable = true;
    distro = "arch";
  };

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
      zoom-us
      slack
      nvd
      qbittorrent
      bottles
      todoist
      xournalpp
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
      krew
      opencode
      snoodev-system
    ]
  );

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
