{ pkgs, ... }:

{
  imports = [
    ./../modules/home-manager/default.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "adriel";
  home.homeDirectory = "/home/adriel";
  # Custom Modules that I'm enabling
  within.kitty.enable = false;
  within.neovim.enable = true;
  within.zsh.enable = true;
  within.discord.enable = true;
  within.kubectl.enable = true;
  within.thunderbird.enable = true;
  within.starship.enable = true;
  within.zoom.enable = true;
  within.ghostty.enable = true;
  # Fonts
  fonts.fontconfig.enable = true;
  # This value determines the Home Manager release that your configuration is
  # compatible with. This helps avoid breakage when a new Home Manager release
  # introduces backwards incompatible changes.
  #
  # You should not change this value, even if you update Home Manager. If you do
  # want to update the value, then make sure to first check the Home Manager
  # release notes.
  home.stateVersion = "24.05"; # Please read the comment before changing.
  nixpkgs.config.allowUnfree = true;

  # The home.packages option allows you to install Nix packages into your
  # environment.
  home.packages = [
    pkgs.vim
    pkgs.firefox
    pkgs.git
    pkgs.go
    pkgs.gotools
    pkgs.wl-clipboard
    pkgs.lshw
    pkgs.nerd-fonts.bigblue-terminal
    pkgs.nerd-fonts.victor-mono
    pkgs.nerd-fonts.zed-mono
    pkgs.nerd-fonts.mononoki
    pkgs.nerd-fonts.heavy-data
    # inputs.ghostty.packages."${pkgs.system}".default
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
    BROWSER = "firefox";
    TERMINAL = "ghostty";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  dconf.settings = {
    "org/gnome/shell" = {
      favorite-apps = [
        "firefox.desktop"
        "kitty.desktop"
        # "ghostty.desktop"
        "com.mitchellh.ghostty.desktop"
      ];
    };
    "org/gnome/desktop/background" = {
      color-shading-type = "solid";
      picture-options = "fill";
      picture-uri = "file://" + ./wallpaper.png;
    };
    "org/gnome/settings-daemon/plugins/color" = {
      night-light-enabled = true;
    };

  };

  xdg.mime.enable = true;
  xdg.mimeApps.enable = true;
  xdg.mimeApps.defaultApplications = {
    "text/plain" = [ "nvim.desktop" ];
    # "text/plain" = [ "com.mitchellh.ghostty.desktop" ];
  };
}
