# modules/system/default.nix
# System-level NixOS modules with within.* options
{ ... }:

{
  imports = [
    ./cosmic.nix
    ./cuda.nix
    ./display-power.nix
    ./gnome.nix
    ./kanata.nix
    ./keyd.nix
    ./mediatek-wifi.nix
    ./plex.nix
    ./redshift.nix
    ./steam.nix
  ];
}
