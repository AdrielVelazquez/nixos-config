# modules/system/default.nix
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
