# modules/home-manager/default.nix
{ inputs, ... }:

{
  imports = [
    inputs.ai-kitten.homeManagerModules.default
    ./firefox.nix
    ./floorp.nix
    ./fonts.nix
    ./gemini-cli.nix
    ./kitty.nix
    ./neovim.nix
    ./niri
    ./snoocert.nix
    ./sops.nix
    ./ssh.nix
    ./starship.nix
    ./vivaldi.nix
    ./yazi.nix
    ./zen-browser.nix
    ./zsh.nix
  ];
}
