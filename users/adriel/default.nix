# users/adriel/default.nix
{ pkgs, config, ... }:

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
  local.niri = {
    enable = true;
    renderDevice = "/dev/dri/by-path/pci-0000:c5:00.0-render";
    ignoreDrmDevice = "/dev/dri/by-path/pci-0000:c4:00.0-card";
    brightnessDevice = "amdgpu_bl1";
    hasDgpu = true;
  };
  local.sops.enable = true;
  sops.secrets.cursor_token = { };
  local.ssh.enable = true;

  xdg.mimeApps = {
    enable = true;
    associations.added = {
      "x-scheme-handler/http" = [ "zen-beta.desktop" ];
      "x-scheme-handler/https" = [ "zen-beta.desktop" ];
      "x-scheme-handler/chrome" = [ "zen-beta.desktop" ];
      "text/html" = [ "zen-beta.desktop" ];
      "application/x-extension-htm" = [ "zen-beta.desktop" ];
      "application/x-extension-html" = [ "zen-beta.desktop" ];
      "application/x-extension-shtml" = [ "zen-beta.desktop" ];
      "application/xhtml+xml" = [ "zen-beta.desktop" ];
      "application/x-extension-xhtml" = [ "zen-beta.desktop" ];
      "application/x-extension-xht" = [ "zen-beta.desktop" ];
      "application/pdf" = [ "okularApplication_pdf.desktop" ];
    };
    defaultApplications = {
      "x-scheme-handler/http" = [ "zen-beta.desktop" ];
      "x-scheme-handler/https" = [ "zen-beta.desktop" ];
      "x-scheme-handler/chrome" = [ "zen-beta.desktop" ];
      "text/html" = [ "zen-beta.desktop" ];
      "application/x-extension-htm" = [ "zen-beta.desktop" ];
      "application/x-extension-html" = [ "zen-beta.desktop" ];
      "application/x-extension-shtml" = [ "zen-beta.desktop" ];
      "application/xhtml+xml" = [ "zen-beta.desktop" ];
      "application/x-extension-xhtml" = [ "zen-beta.desktop" ];
      "application/x-extension-xht" = [ "zen-beta.desktop" ];
      "application/pdf" = [ "okularApplication_pdf.desktop" ];
    };
  };
  xdg.configFile."mimeapps.list".force = true;
  xdg.dataFile."applications/mimeapps.list".force = true;

  home.sessionVariables = {
    EDITOR = "nvim";
    BROWSER = "zen-browser";
    TERMINAL = "kitty";
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
      llama-cpp
      opencode
      cursor-cli
    ]
  );
  # In your home-manager configuration
  services.gnome-keyring.enable = true;

  programs.git = {
    enable = true;
    signing.format = null;
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

  home.file.".config/opencode" = {
    # source = ../../dotfiles/opencode;
    source = ../../dotfiles/opencode;
    recursive = true;
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

  programs.ai-kitten = {
    enable = true;
    keybinding = "ctrl+shift+a";
    settings = {
      provider = "cursor";
      max_context_lines = 0;
      cursor_api_key_file = config.sops.secrets.cursor_token.path;
      cursor = {
        command = "cursor-agent";
        mode = "ask";
        model = "composer-2-fast";
        timeout_seconds = 60;
        stream = true;
      };
      panel = {
        # "vertical"   -> vsplit (chat sidebar on the side)
        # "horizontal" -> hsplit (banner stacked above/below)
        orientation = "horizontal";
        # Which side of the active window the panel lands on.
        # Defaulted from orientation:
        #   "vertical"   -> "right"
        #   "horizontal" -> "bottom"
        # Override here only if you want left/top instead.
        edge = "bottom";
        # Fraction of available space; mapped to kitty `--bias=N`.
        ratio = 0.25;
      };
    };
  };
}
