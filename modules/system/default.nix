{ ... }:

{
  imports = [
    ./cuda.nix
    ./keyd.nix
    ./kanata.nix
    ./steam.nix
    ./plex.nix
    ./gnome.nix
    ./cosmic.nix
    ./redshift.nix
    ./sops.nix
    # ./ssh-agent.nix
  ];
}
