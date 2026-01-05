# modules/mac-services/karabiner.nix
# Karabiner-Elements configuration for macOS
#
# This module manages the Karabiner-Elements configuration file.
# Karabiner-Elements itself should be installed via Homebrew cask.
#
# Note: Karabiner-Elements modifies its config file directly, so we use
# an activation script to copy (not symlink) our config on darwin-rebuild.
#
# Features:
# - Colemak-DH layout
# - Home row mods (ARST/NEIO with Opt/Cmd/Ctrl/Shift) using lazy modifiers
# - Caps Lock → Escape (tap) / Hyphen (hold)
# - Space → Space (tap) / Nav layer (hold) with vim-style arrows
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.karabiner;

  karabinerConfig = ../../dotfiles/karabiner/karabiner.json;
in
{
  options.local.karabiner = {
    enable = lib.mkEnableOption "Karabiner-Elements keyboard remapping";
  };

  config = lib.mkIf cfg.enable {
    # Use an activation script to copy the config file
    # This ensures our config takes precedence over Karabiner's modifications
    home-manager.sharedModules = [
      {
        home.activation.karabiner = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          $DRY_RUN_CMD mkdir -p ~/.config/karabiner
          $DRY_RUN_CMD cp -f ${karabinerConfig} ~/.config/karabiner/karabiner.json
          $VERBOSE_ECHO "Karabiner config copied to ~/.config/karabiner/karabiner.json"
        '';
      }
    ];
  };
}
