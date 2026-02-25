# users/adriel.velazquez/linux.nix
{ pkgs, ... }:

{
  imports = [
    ./modules.nix
  ];

  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
  home.username = "adriel.velazquez";
  home.homeDirectory = "/home/adriel.velazquez";

  local.zen-browser = {
    enable = true;
    enableVaapi = true;
    useWayland = true;
    enableGpuRecovery = true;
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

  home.packages = with pkgs; [
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
  ];

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
