# modules/home-manager/default.nix
# Home Manager modules with local.* options
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
