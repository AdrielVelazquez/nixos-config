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
    # ./sops.nix  # Moved to home-manager (see modules/home-manager/sops.nix)
    # ./ssh-agent.nix
  ];
}
