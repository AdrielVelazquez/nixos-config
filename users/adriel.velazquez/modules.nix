# users/adriel.velazquez/modules.nix
# Module enables for adriel.velazquez user (work systems)
{ ... }:

{
  imports = [
    ../../modules/home-manager/default.nix
  ];

  # Shell & Terminal
  local.zsh.enable = true;
  local.kitty.enable = true;
  local.starship.enable = true;

  # Editor
  local.neovim.enable = true;

  # Development
  local.kubectl.enable = true;

  # Applications
  local.zoom.enable = true;
  local.fonts.enable = true;

  # Security & Secrets
  local.sops.enable = true;
  local.ssh.enable = true;
}
