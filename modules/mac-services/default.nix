# modules/mac-services/default.nix
# macOS service modules with local.* options
{ ... }:

{
  imports = [
    ./karabiner.nix
  ];
}
