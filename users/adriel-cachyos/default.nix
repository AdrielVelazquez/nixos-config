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
  local.niri = {
    enable = true;
    useSystemHyprlock = true;
    fuzzel.enable = true;
    walker.enable = false;
    hyprlock.suspendTimeoutSeconds = 1200;
    kanshi.profiles = [
      {
        profile = {
          name = "undocked";
          outputs = [
            {
              criteria = "eDP-1";
              status = "enable";
              scale = 1.1;
            }
          ];
        };
      }
      {
        profile = {
          name = "docked";
          outputs = [
            {
              criteria = "eDP-1";
              status = "disable";
            }
            {
              criteria = "*";
              status = "enable";
              scale = 1.0;
            }
          ];
        };
      }
    ];
  };

  local.zoom.enable = true;

  local.web-mime-defaults.enable = true;

  # Shell & Terminal
  local.zsh.enable = true;
  local.kitty = {
    enable = true;
    enableGpuRecovery = true;
  };
  local.ai-kitten = {
    enable = true;
  };

  local.starship.enable = true;
  local.gemini-cli.enable = true;
  local.codex-cli.enable = true;
  local.cursor-cli.enable = true;

  # Editor
  local.neovim.enable = true;

  # Applications
  local.fonts.enable = true;

  # Security & Secrets
  local.sops.enable = true;
  local.ssh = {
    enable = true;
    additionalHosts =
      let
        sshca = {
          hostname = "sshca.orch.ue1.snooguts.net";
          user = null;
          identityFile = null;
          forwardAgent = true;
          strictHostKeyChecking = "yes";
        };
      in
      {
        inherit sshca;
        "sshca.orch.ue1.snooguts.net" = sshca;
      };
  };
  local.snoocert.enable = true;

  local.zen-browser = {
    enable = true;
    enableVaapi = true;
    useWayland = true;
    enableExtensionDebugLogging = true;
  };
  local.zen-domain-tab-grouper.enable = true;

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
      wl-clipboard
      lshw
      slack
      nvd
      qbittorrent
      # bottles
      todoist
      kooha
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
