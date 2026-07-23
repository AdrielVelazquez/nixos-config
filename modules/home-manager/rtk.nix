{ pkgs, ... }:

let
  rtk = import ./rtk-path-test-dead-code.nix { inherit pkgs; };
in
{
  home.packages = [ rtk ];
}
