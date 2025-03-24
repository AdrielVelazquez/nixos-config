{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.kitty;
in
{
  options.within.kitty.enable = mkEnableOption "Enables Kitty Terminal Settings";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.kitty
      pkgs.fzf
    ];
    programs.kitty.enable = true;
    programs.kitty.shellIntegration.enableZshIntegration = true;
    programs.kitty.settings = {
      scrollback_pager_history_size = 60;
      font_family = "Inconsolata Nerd Font Mono Regular";
      font_size = "16.0";
      tab_bar_edge = "top";
      tab_bar_style = "slant";
      # Allow Remote
      # Following Plugins that require remote control
      # kitty-scrollback.nvim
      allow_remote_control = "socket-only";
      # Required for Kitty Scrollback
      listen_on = "unix:/tmp/kitty";

      shell_integration = "enabled";
      # Mapping to use nvim as my scrollback scrollback_pager_history
      editor = "nvim";
      # kitty-scrollback.nvim Kitten alias
      action_alias = "kitty_scrollback_nvim kitten $HOME/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py";
      # Nerd Fonts v3.2.0

      symbol_map = "U+e000-U+e00a,U+ea60-U+ebeb,U+e0a0-U+e0c8,U+e0ca,U+e0cc-U+e0d7,U+e200-U+e2a9,U+e300-U+e3e3,U+e5fa-U+e6b1,U+e700-U+e7c5,U+ed00-U+efc1,U+f000-U+f2ff,U+f000-U+f2e0,U+f300-U+f372,U+f400-U+f533,U+f0001-U+f1af0 Symbols Nerd Font Mono";
    };
    programs.kitty.themeFile = "MonaLisa";
    programs.kitty.keybindings = {
      "ctrl+shift+f" =
        "launch --type=overlay --stdin-source=@screen_scrollback /bin/sh -c \"fzf --no-sort --no-mouse --exact -i --tac | kitty +kitten clipboard\"";
      "kitty_mod+h" = "kitty_scrollback_nvim";
      "kitty_mod+g" = " kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
    };

  };
}
