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
    # Font Settings
    # TODO
    programs.kitty.settings = {
      font_family = "Maple Mono NF";
      bold_font = "auto";
      italic_font = "auto";
      bold_italic_font = "auto";
      font_size = "16.0";
      # font_features = "+zero +liga +calt -ss01 -ss02 -ss08 -ss06 +ss03";
      font_features = "MapleMono-NF-Regular -calt +zero";
    };
    # Tab bar settings
    programs.kitty.settings = {
      tab_bar_edge = "top";
      tab_bar_align = "left";
      tab_bar_min_tabs = "1";
      tab_activity_symbol = "none";
      tab_bar_margin_height = "0.0 0.0";
      tab_bar_margin_width = "0.0";
      active_tab_font_style = "bold";
      tab_bar_style = "custom";
      tab_title_template = "{f'{title[:30]}…' if title.rindex(title[-1]) + 1 > 30 else (title.center(6) if (title.rindex(title[-1]) + 1) % 2 == 0 else title.center(5))}";
    };

    # Linux settings
    programs.kitty.settings = {
      # Linux Specific Options
      linux_display_server = "wayland";
    };

    # Mac settings
    programs.kitty.settings = {
      # Mac Specific Options
      macos_option_as_alt = "yes";
      macos_colorspace = "displayp3";
    };

    # General settings
    programs.kitty.settings = {
      scrollback_pager_history_size = 60;
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
      hide_window_decorations = "no";

      # Nerd Fonts v3.2.0
      symbol_map = "U+e000-U+e00a,U+ea60-U+ebeb,U+e0a0-U+e0c8,U+e0ca,U+e0cc-U+e0d7,U+e200-U+e2a9,U+e300-U+e3e3,U+e5fa-U+e6b1,U+e700-U+e7c5,U+ed00-U+efc1,U+f000-U+f2ff,U+f000-U+f2e0,U+f300-U+f372,U+f400-U+f533,U+f0001-U+f1af0 Symbols Nerd Font Mono";
    };

    programs.kitty.themeFile = "MonaLisa";

    programs.kitty.keybindings = {
      "ctrl+shift+f" =
        "launch --type=overlay --stdin-source=@screen_scrollback /bin/sh -c \"${pkgs.fzf}/bin/fzf --no-sort --no-mouse --exact -i --tac | kitty +kitten clipboard\"";
      "kitty_mod+h" = "kitty_scrollback_nvim";
      "kitty_mod+g" = " kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
      # This is mostly to mimic the same behaviour from linux to mac
      "ctrl+shift+c" = "copy_to_clipboard";
      "ctrl+shift+v" = "paste_from_clipboard";
    };

    home.file = {
      ".config/kitty/tab_bar.py" = {
        source = ../../dotfiles/kitty/tab_bar.py;
        # recursive = true;
      };
    };
  };
}
