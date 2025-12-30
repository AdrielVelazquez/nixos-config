# modules/mac-services/kanata.nix
# macOS Kanata keyboard remapper configuration
#
# Note: nix-darwin can't start kanata as a proper service due to macOS
# security requirements (Input Monitoring permission). This module sets up
# the config file; kanata must be started manually or via a workaround.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.kanata;

  # Read shared layout from dotfiles
  layoutConfig = builtins.readFile ../../dotfiles/kanata/layout.kbd;

  # macOS-specific defcfg
  fullKanataConfig = ''
    (defcfg
      macos-dev-names-include (
        "Apple Internal Keyboard / Trackpad"
      )
    )

    ${layoutConfig}
  '';

  kanataConfigFile = pkgs.writeText "kanata.kbd" fullKanataConfig;
in
{
  options.local.kanata.enable = lib.mkEnableOption "Enables Kanata on macOS";

  config = lib.mkIf cfg.enable {
    # Place config file where the startup script expects it
    environment.etc."kanata.kbd".source = kanataConfigFile;

    # Keep the existing binary for manual startup
    environment.etc."kanata-nix".source = ./kanata/kanata_macos_arm64;
  };
}
