# modules/home-manager/default.nix
#
# Modules safe to load on every HM closure.
{ ... }:

{
  imports = [
    ./firefox.nix
    ./floorp.nix
    ./fonts.nix
    ./ghostty.nix
    ./git.nix
    ./headroom.nix
    ./kitty.nix
    ./neovim.nix
    ./niri
    ./nixpkgs-review.nix
    ./noctalia.nix
    ./opencode.nix
    ./opencode-routing.nix
    ./openspec.nix
    ./pi
    ./rio.nix
    ./rtk.nix
    ./snoocert.nix
    ./sops.nix
    ./ssh.nix
    ./starship.nix
    ./tuios.nix
    ./vivaldi.nix
    ./web-mime-defaults.nix
    ./yazi.nix
    ./zen-domain-tab-grouper
    ./zen-browser.nix
    ./zoom.nix
    ./zsh.nix
  ];
}
