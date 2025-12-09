{ pkgs, ... }:

{
  imports = [
    ./adriel-modules.nix
    ../modules/home-manager/default.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "adriel.velazquez";
  home.homeDirectory = "/home/adriel.velazquez";

  nixpkgs.config.allowUnfree = true;
  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.
  home.packages = [
    pkgs.firefox
    pkgs.vim
    pkgs.brave
    pkgs.git
    pkgs.go
    pkgs.gotools
    pkgs.wl-clipboard
    pkgs.lshw
    pkgs.qbittorrent
    pkgs.bottles
    pkgs.todoist
    pkgs.xournalpp
    pkgs._1password-gui
    pkgs.gh
    pkgs.nix-prefetch-github
    pkgs.jq
    pkgs.ripgrep
    pkgs.openssl
    pkgs.ed
    pkgs.qalculate-qt
    pkgs.gemini-cli
    pkgs.kitty
    pkgs.slack
    pkgs.infrared
    pkgs.snoologin
    pkgs.reddit-lint-py
    pkgs.ollama
    pkgs.docker
    pkgs.code-cursor
    pkgs.tilt
    pkgs.cloudflared
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    # # Building this configuration will create a copy of 'dotfiles/screenrc' in
    # # the Nix store. Activating the configuration will then make '~/.screenrc' a
    # # symlink to the Nix store copy.
    # ".screenrc".source = dotfiles/screenrc;

    # # You can also set the file content immediately.
    # ".gradle/gradle.properties".text = ''
    #   org.gradle.console=verbose
    #   org.gradle.daemon.idletimeout=3600000
    # '';
  };
  home.sessionVariables = {
    EDITOR = "nvim";
    # BROWSER = "firefox";
    # Force applications to use the nix-system-graphics drivers
    LD_LIBRARY_PATH = "/run/opengl-driver/lib:$LD_LIBRARY_PATH";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;
  programs.zsh.enable = true;
  programs.git = {
    enable = true;
    settings = {
      push = {
        default = "current";
      };
      # The URL section is nested one level deeper
      url = {
        "git@github.snooguts.net:" = {
          insteadOf = "https://github.snooguts.net/";
        };
      };
    };
  };
  home.sessionPath = [
    "$HOME/go/bin"
  ];
}
