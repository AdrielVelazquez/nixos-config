# modules/system/default.nix
# System-level NixOS modules with local.* options
{ ... }:

{
  imports = [
    ./cosmic.nix
    ./cuda.nix
    ./kanata.nix
    ./mediatek-wifi.nix
    ./plex.nix
    ./steam.nix
    ./wifi-profiles.nix
  ];
}
