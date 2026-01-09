# modules/home-manager/default.nix
{ ... }:

{
  imports = [
    ./firefox.nix
    ./floorp.nix
    ./fonts.nix
    ./kitty.nix
    ./neovim.nix
    ./sops.nix
    ./ssh.nix
    ./starship.nix
    ./vivaldi.nix
    ./zen-browser.nix
    ./zsh.nix
  ];
}
