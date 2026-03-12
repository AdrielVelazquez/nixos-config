{ lib, ... }:

{
  imports = [ ../adriel.velazquez/linux.nix ];
  home.username = lib.mkForce "adriel";
  home.homeDirectory = lib.mkForce "/home/adriel";
}
