{ pkgs, config, ... }:

{
  imports = [
    ./../modules/home-manager/default.nix
  ];
  within.kitty.enable = true;
  within.neovim.enable = true;
  within.zsh.enable = true;
  within.starship.enable = true;
  within.fonts.enable = true;
  within.kubectl.enable = true;
  within.zoom.enable = true;
}
