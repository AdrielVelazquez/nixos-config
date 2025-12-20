# modules/mac-services/kanata.nix
# macOS Kanata keyboard remapper configuration
{ lib, config, ... }:

let
  cfg = config.within.kanata;
in
{
  options.within.kanata.enable = lib.mkEnableOption "Enables Kanata on macOS";

  config = lib.mkIf cfg.enable {
    environment.etc."mac-kanata.kbd".source = ../../dotfiles/kanata/mac-config.kdb;
    environment.etc."kanata-nix".source = ./kanata/kanata_macos_arm64;
  };
}
