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
    ./headroom-pi.nix
    ./kitty.nix
    ./neovim.nix
    ./niri
    ./nixpkgs-review.nix
    ./noctalia.nix
    ./opencode.nix
    ./omp.nix
    ./opencode-routing.nix
    ./openspec.nix
    ./pi.nix
    ./pi-capabilities.nix
    ./pi-ui.nix
    ./pi-lsp.nix
    ./pi-ghost.nix
    ./pi-model-roles.nix
    ./pi-work.nix
    ./pi-routing.nix
    ./pi-workflow.nix
    ./openspec-pi.nix
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
