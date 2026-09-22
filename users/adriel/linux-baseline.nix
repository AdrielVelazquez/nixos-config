{ pkgs, ... }:

{
  imports = [
    ../../modules/home-manager/default.nix
  ];

  home.stateVersion = "24.05";
  programs.home-manager.enable = true;
  home.username = "adriel";
  home.homeDirectory = "/home/adriel";

  local.zsh.enable = true;
  local.kitty.enable = true;
  local.starship.enable = true;
  local.neovim.enable = true;
  local.opencode.enable = true;
  local.openspec.enable = true;
  local.fonts.enable = true;
  local.sops.enable = true;
  local.ssh.enable = true;
  local.git.enable = true;
  local.headroom = {
    enable = true;
    wrapDefaults = {
      memory = true;
      codeGraph = true;
    };
    tuning = {
      # Cost-focused beta trial; keep the steering text stable across turns.
      # Input compression uses the upstream coding profile in cache mode.
      reduceOutputTokens = true;
      verbosityLevel = 3;
    };
    proxyEnv = {
      HEADROOM_ROLLOUT_CHANNEL = "beta";
      HEADROOM_EFFORT_ROUTER = "0";
      HEADROOM_VERBOSITY_AUTOTUNE = "0";
      HEADROOM_OUTPUT_HOLDOUT = "0";
      HEADROOM_TOOL_DESC_MAX_CHARS = "1024";
      HEADROOM_TOOL_DESC_STRIP_SEMANTIC = "0";
    };
  };
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
