{ pkgs, ... }:

{
  imports = [
    ./../modules/home-manager/default.nix
    ./../modules/reddit/default.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "adriel.velazquez";
  home.homeDirectory = "/Users/adriel.velazquez";

  # Custom Modules that I'm enabling
  within.ghostty.enable = true;
  # within.kitty.enable = true;

  within.neovim.enable = true;
  within.zsh.enable = true;
  within.starship.enable = true;
  # within.infrared.enable = true;
  # within.zoom.enable = true;
  # Fonts
  # fonts.fontconfig.enable = true;
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
    # pkgs.firefox
    pkgs.git
    pkgs.gh
    pkgs.nerd-fonts.bigblue-terminal
    pkgs.nerd-fonts.victor-mono
    pkgs.nerd-fonts.zed-mono
    pkgs.nerd-fonts.mononoki
    pkgs.nerd-fonts.heavy-data
    pkgs.nerd-fonts.inconsolata
    pkgs.rcm
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/kanata/config.kdb" = {
      source = ../dotfiles/kanata/config.kdb;
    };
    ".config/rcm/bindings.conf".text = ''
      .txt = ${pkgs.neovim}/bin/nvim
    '';
  };
  home.sessionVariables = {
    EDITOR = "nvim";
  };
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

}
