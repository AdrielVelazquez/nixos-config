# modules/mac-services/default.nix
# macOS service modules with within.* options
{ ... }:

{
  imports = [
    ./kanata.nix
  ];
}
