# modules/mac-services/karabiner.nix
# Uses activation script to copy config (Karabiner modifies its own file)
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
      # Must be a proper module function to receive home-manager's lib (with lib.hm)
      (
        { lib, ... }:
        {
          home.activation.karabiner = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            $DRY_RUN_CMD mkdir -p ~/.config/karabiner
            $DRY_RUN_CMD cp -f ${karabinerConfig} ~/.config/karabiner/karabiner.json
            $VERBOSE_ECHO "Karabiner config copied to ~/.config/karabiner/karabiner.json"
          '';
        }
      )
    ];
  };
}
