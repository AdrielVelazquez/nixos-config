{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.ghostty;
in
{
  options.within.ghostty.enable = mkEnableOption "Enables ghostty Terminal Settings";

  config = mkIf cfg.enable {

    # home.packages = lib.optionalAttrs (pkgs.stdenv.isLinux) [
    #   inputs.ghostty.packages."${pkgs.system}".default
    # ];
    nixpkgs = {
      overlays = [
        inputs.brew-nix.overlays.default
      ];
    };
    home.packages = (
      if pkgs.stdenv.isLinux then
        [
          inputs.ghostty.packages."${pkgs.system}".default
        ]
      else
        [ pkgs.brewCasks.ghostty ]
    );
    home.file = {
      ".config/ghostty/config" = {
        source = (
          if pkgs.stdenv.isLinux then ../../dotfiles/ghostty/config else ../../dotfiles/ghostty/mac-config
        );
      };
    };
  };
}
