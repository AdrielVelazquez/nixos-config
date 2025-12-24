# users/adriel.velazquez-modules.nix
# Module enables for adriel.velazquez user (work systems)
{ ... }:

{
  imports = [
    ../modules/home-manager/default.nix
  ];

  # Shell & Terminal
  within.zsh.enable = true;
  within.kitty.enable = true;
  within.starship.enable = true;

  # Editor
  within.neovim.enable = true;

  # Development
  within.kubectl.enable = true;

  # Applications
  within.zoom.enable = true;
  within.fonts.enable = true;

  # Security & Secrets
  within.sops.enable = true;
  within.ssh.enable = true;
}
