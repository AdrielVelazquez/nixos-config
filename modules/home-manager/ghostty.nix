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
    home.packages = (
      if pkgs.stdenv.isLinux then
        [
          inputs.ghostty.packages."${pkgs.system}".default
        ]
      else
        [ ]
    );
    # inputs.nix-homebrew = lib.optionalAttrs (pkgs.stdenv.isDarwin) {
    #   casks = [
    #     "ghostty"
    #   ];
    # };

    home.file = {
      ".config/ghostty/config" = {
        source = (
          if pkgs.stdenv.isLinux then ../../dotfiles/ghostty/config else ../../dotfiles/ghostty/mac-config
        );
      };
    };
  };
}
