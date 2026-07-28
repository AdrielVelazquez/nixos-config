# modules/services/default.nix
{ ... }:

{
  imports = [
    ./docker.nix
    ./mullvad.nix
    ./ollama.nix
  ];
}
