# users/adriel/default.nix
{ pkgs, inputs, ... }:

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
  local.ssh.enable = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "zen-browser";
    TERMINAL = "kitty";
  };

  home.sessionPath = [
    "$HOME/go/bin"
  ];

  home.packages =
    (with pkgs; [
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
      _1password-gui
      code-cursor
      popsicle
      obsidian
      llama-cpp
    ])
    ++ (with inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}; [
      jules
    ]);
  # In your home-manager configuration
  services.gnome-keyring.enable = true;

  programs.git = {
    enable = true;
    settings = {
      user.name = "Adriel Velazquez";
      user.email = "AdrielVelazquez@gmail.com";
      init.defaultBranch = "main";
      push.default = "current";
      pull.rebase = false;
      url = {
        "git@github.com:" = {
          insteadOf = "https://github.com/";
        };
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
