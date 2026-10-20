# modules/home-manager/ghostty.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.ghostty;
in
{
  options.local.ghostty = {
    enable = lib.mkEnableOption "Enables Ghostty Terminal Settings (trial alongside Kitty)";
  };

  config = lib.mkIf cfg.enable {
    programs.ghostty = {
      enable = true;
      enableZshIntegration = true;
      # Tabs, splits and sessions live in tuios: start from an empty keymap so
      # every chord reaches it, then bind back only what the terminal owns.
      clearDefaultKeybinds = true;

      settings = {
        font-family = "Maple Mono NF";
        font-size = 11;
        font-feature = [
          "-calt"
          "+zero"
        ];

        # Bundled theme, the same scheme as Kitty's MonaLisa.
        theme = "Mona Lisa";

        # OLED: force pure black, no transparency
        background = "#000000";
        background-opacity = 1.0;

        window-show-tab-bar = "never";
        confirm-close-surface = false;

        keybind = [
          "ctrl+shift+c=copy_to_clipboard"
          "ctrl+shift+v=paste_from_clipboard"
          "ctrl+shift+f=start_search"
          "ctrl+shift+n=new_window"
          "shift+page_up=scroll_page_up"
          "shift+page_down=scroll_page_down"
        ];
      }
      # Like Kitty's startup session: only the first surface opens tuios, so
      # later windows stay plain shells.
      // lib.optionalAttrs config.local.tuios.enable {
        initial-command = lib.getExe' config.local.tuios.package "tuios";
      };
    };
  };
}
