{ pkgs, config, ... }:

{
  imports = [
    ./adriel.velazquez-modules.nix
  ];
  # Home Manager needs a bit of information about you and the paths it should
  # manage.
  home.username = "adriel.velazquez";
  home.homeDirectory = "/Users/adriel.velazquez";

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
    pkgs.git
    pkgs.gh
    pkgs.nerd-fonts.bigblue-terminal
    pkgs.nerd-fonts.victor-mono
    pkgs.nerd-fonts.zed-mono
    pkgs.nerd-fonts.mononoki
    pkgs.nerd-fonts.heavy-data
    pkgs.nerd-fonts.inconsolata
    pkgs.rcm
    pkgs.duti
    pkgs.go
    pkgs.google-cloud-sdk
    pkgs.thrift
    pkgs.rsync
    pkgs.awscli2
    pkgs.brave
    pkgs.watch
    pkgs.graphviz
    pkgs.ripgrep
  ];

  # Home Manager is pretty good at managing dotfiles. The primary way to manage
  # plain files is through 'home.file'.
  home.file = {
    ".config/kanata/config.kdb" = {
      source = ../dotfiles/kanata/mac-config.kdb;
    };
    ".config/rcm/bindings.conf".text = ''
      .txt = ${pkgs.neovim}/bin/nvim
    '';
  };
  home.sessionVariables = {
    EDITOR = "${pkgs.neovim}/bin/nvim";
  };
  home.sessionPath = [
    "/etc/profiles/per-user/adriel.velazquez/bin/"
    "/opt/reddit/bin/"
    "${config.home.homeDirectory}/go/bin"
  ];
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

}
