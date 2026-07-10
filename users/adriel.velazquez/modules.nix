# users/adriel.velazquez/modules.nix
# Module enables for adriel.velazquez user (work systems)
{ ... }:

{
  imports = [
    ../../modules/home-manager/default.nix
  ];

  # Shell & Terminal
  local.zsh.enable = true;
  local.kitty = {
    enable = true;
    enableGpuRecovery = true;
  };
  local.starship.enable = true;
  local.codex-cli.enable = true;
  local.gemini-cli.enable = true;

  # Editor
  local.neovim.enable = true;

  # Applications
  local.fonts.enable = true;

  # Security & Secrets
  local.sops = {
    enable = true;
    ageKeyFile = "/Users/adriel.velazquez/.config/sops/age/keys.txt";
  };
  local.ssh.enable = true;
}
