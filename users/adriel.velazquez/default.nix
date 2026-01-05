# users/adriel.velazquez/default.nix (macOS)
{ pkgs, config, ... }:

{
  imports = [
    ./modules.nix
  ];

  home.username = "adriel.velazquez";
  home.homeDirectory = "/Users/adriel.velazquez";
  home.stateVersion = "24.05";
  programs.home-manager.enable = true;

  home.sessionVariables = {
    EDITOR = "${pkgs.neovim}/bin/nvim";
  };

  home.sessionPath = [
    "/etc/profiles/per-user/adriel.velazquez/bin/"
    "/opt/reddit/bin/"
    "${config.home.homeDirectory}/go/bin"
  ];

  home.file = {
    ".config/rcm/bindings.conf".text = ''
      .txt = ${pkgs.neovim}/bin/nvim
    '';
  };

  home.packages = with pkgs; [
    vim
    git
    gh
    ripgrep
    just
    rcm
    duti
    watch
    go
    google-cloud-sdk
    thrift
    rsync
    awscli2
    graphviz
    code-cursor
    brave
  ];
}
