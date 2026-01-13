# users/adriel/default.nix
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

  # Gemini API key from sops secrets
  sops.secrets.gemini_api_key = { };

  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "zen-browser";
    TERMINAL = "kitty";
  };

  # Load API keys from sops secrets at session start
  home.sessionVariablesExtra = ''
    if [[ -r "$HOME/.config/sops-nix/secrets/gemini_api_key" ]]; then
      export GEMINI_API_KEY="$(cat $HOME/.config/sops-nix/secrets/gemini_api_key)"
    fi
  '';

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
    _1password-gui
    code-cursor
    popsicle
  ];

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
  programs.gemini-cli = {
    enable = true;
    settings = {
      model = "gemini-3-pro-preview";
    };
  };
}
