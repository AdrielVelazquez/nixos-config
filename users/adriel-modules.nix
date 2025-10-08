{ ... }:

{
  imports = [
    ./../modules/home-manager/default.nix
  ];
  within.kitty.enable = true;
  within.neovim.enable = true;
  within.zsh.enable = true;
  within.discord.enable = true;
  within.kubectl.enable = true;
  within.starship.enable = true;
  within.zoom.enable = true;
  within.ghostty.enable = false;
  within.fonts.enable = true;
}
