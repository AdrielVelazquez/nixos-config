# modules/home-manager/default.nix
{ ... }:

{
  imports = [
    ./firefox.nix
    ./fonts.nix
    ./kitty.nix
    ./neovim.nix
    ./sops.nix
    ./ssh.nix
    ./starship.nix
    ./zsh.nix
  ];
}
