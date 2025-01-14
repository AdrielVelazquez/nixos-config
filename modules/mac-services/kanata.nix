{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.kanata;
in
{
  options.within.kanata.enable = mkEnableOption "Enables kanata Settings";
  config = mkIf cfg.enable {
    environment.etc."mac-kanata.kbd" = {
      source = ../../dotfiles/kanata/mac-config.kdb;
    };
    environment.etc."kanata-nix" = {
      source = ./kanata/kanata_macos_arm64;
    };
  };

}
