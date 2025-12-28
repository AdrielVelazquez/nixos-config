# modules/system/default.nix
# System-level NixOS modules with local.* options
{ ... }:

{
  imports = [
    ./cosmic.nix
    ./cuda.nix
    ./gnome.nix
    ./kanata.nix
    ./keyd.nix
    ./mediatek-wifi.nix
    ./plex.nix
    ./redshift.nix
    ./steam.nix
    ./wifi-profiles.nix
  ];
}
