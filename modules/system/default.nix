{ ... }:

{
  imports = [
    ./cuda.nix
    ./keyd.nix
    ./kanata.nix
    ./steam.nix
    ./plex.nix
    ./falcon/falcon-sensor.nix
    ./gnome.nix
    ./cosmic.nix
    ./redshift.nix
  ];
}
