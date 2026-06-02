# modules/system/default.nix
{ ... }:

{
  imports = [
    ./apple-studio-display-brightness.nix
    ./cosmic.nix
    ./cuda.nix
    ./kanata.nix
    ./mediatek-wifi.nix
    ./niri.nix
    ./plex.nix
    ./steam.nix
    ./wifi-profiles.nix
    ./zsa-keyboard.nix
  ];
}
