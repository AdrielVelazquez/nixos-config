# modules/services/default.nix
# Service modules with within.* options
{ ... }:

{
  imports = [
    ./docker.nix
    ./mullvad.nix
    ./ollama.nix
    ./powertop.nix
    ./solaar.nix
    ./tlp.nix
  ];
}
