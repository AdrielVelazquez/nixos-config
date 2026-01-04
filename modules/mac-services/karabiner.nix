# modules/mac-services/karabiner.nix
# Karabiner-Elements configuration for macOS
#
# This module manages the Karabiner-Elements configuration file.
# Karabiner-Elements itself should be installed via Homebrew cask.
#
# Features:
# - Colemak-DH layout
# - Home row mods (ARST/NEIO with Alt/Cmd/Ctrl/Shift)
# - Caps Lock → Escape (tap) / Hyphen (hold)
# - Space → Space (tap) / Nav layer (hold) with vim-style arrows
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.karabiner;

  karabinerConfigDir = ../../dotfiles/karabiner;
in
{
  options.local.karabiner = {
    enable = lib.mkEnableOption "Karabiner-Elements keyboard remapping";
  };

  config = lib.mkIf cfg.enable {
    # Symlink the karabiner config to the expected location
    # Karabiner looks for config in ~/.config/karabiner/
    home-manager.sharedModules = [
      {
        xdg.configFile."karabiner/karabiner.json" = {
          source = "${karabinerConfigDir}/karabiner.json";
        };
      }
    ];
  };
}

