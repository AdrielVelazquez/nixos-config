# parts/checks.nix
# Flake checks (validate configurations build)
{ config, localLib, ... }:

let
  inherit (localLib) systems;

in
{
  flake.checks = {
    ${systems.linux} = {
      # NixOS configuration checks
      razer14 = config.flake.nixosConfigurations.razer14.config.system.build.toplevel;
      dell = config.flake.nixosConfigurations.dell.config.system.build.toplevel;

      # Home Manager configuration checks
      home-adriel = config.flake.homeConfigurations.adriel.activationPackage;
      home-reddit-framework13 = config.flake.homeConfigurations.reddit-framework13.activationPackage;
    };
    ${systems.darwin} = {
      # Darwin configuration check
      reddit-mac = config.flake.darwinConfigurations.PNH46YXX3Y.config.system.build.toplevel;
    };
  };
}
