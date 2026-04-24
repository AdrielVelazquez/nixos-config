# modules/home-manager/default.nix
#
# Modules safe to load on every HM closure. Modules that pull in private
# flake inputs (currently: ai-kitten) live outside this bundle and are
# imported per-user where opted in.
{ ... }:

{
  imports = [
    ./firefox.nix
    ./floorp.nix
    ./fonts.nix
    ./gemini-cli.nix
    ./git.nix
    ./kitty.nix
    ./neovim.nix
    ./niri
    ./snoocert.nix
    ./sops.nix
    ./ssh.nix
    ./starship.nix
    ./vivaldi.nix
    ./web-mime-defaults.nix
    ./yazi.nix
    ./zen-browser.nix
    ./zoom.nix
    ./zsh.nix
  ];
}
