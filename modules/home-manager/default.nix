# modules/home-manager/default.nix
# Home Manager modules with local.* options
{ ... }:

{
  imports = [
    ./firefox.nix
    ./fonts.nix
    ./input-remapper.nix
    ./kanata.nix
    ./kitty.nix
    ./kubectl.nix
    ./neovim.nix
    ./sops.nix
    ./ssh.nix
    ./starship.nix
    ./zsh.nix
  ];
}
