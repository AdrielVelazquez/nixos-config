# modules/system/default.nix
# System-level NixOS modules with within.* options
{ ... }:

{
  imports = [
    ./cosmic.nix
    ./cuda.nix
    ./gnome.nix
    ./kanata.nix
    ./keyd.nix
    ./plex.nix
    ./redshift.nix
    ./steam.nix
  ];
}
