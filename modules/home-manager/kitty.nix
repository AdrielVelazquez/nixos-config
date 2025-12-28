# modules/home-manager/kitty.nix
# Kitty terminal configuration
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.within.kitty;
in
{
  options.within.kitty.enable = lib.mkEnableOption "Enables Kitty Terminal Settings";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      kitty
      fzf
    ];

    programs.kitty = {
      enable = true;
      shellIntegration.enableZshIntegration = true;
      themeFile = "MonaLisa";

      settings = lib.mkMerge [
        # ==========================================================================
        # Font Settings
        # ==========================================================================
        {
          font_family = "Maple Mono NF";
          bold_font = "auto";
          italic_font = "auto";
          bold_italic_font = "auto";
          font_size = "16.0";
          font_features = "MapleMono-NF-Regular -calt +zero";
        }

        # ==========================================================================
        # Tab Bar Settings
        # ==========================================================================
        {
          tab_bar_edge = "top";
          tab_bar_align = "left";
          tab_bar_min_tabs = "1";
          tab_activity_symbol = "none";
          tab_bar_margin_height = "0.0 0.0";
          tab_bar_margin_width = "0.0";
          active_tab_font_style = "bold";
          tab_bar_style = "custom";
          tab_title_template = "{f'{title[:30]}…' if title.rindex(title[-1]) + 1 > 30 else (title.center(6) if (title.rindex(title[-1]) + 1) % 2 == 0 else title.center(5))}";
        }

        # ==========================================================================
        # OLED Optimizations
        # ==========================================================================
        {
          # OVERRIDE: Force pure OLED black
          background = "#000000";

          # OVERRIDE: Ensure opacity is 100% (transparency kills OLED savings)
          background_opacity = "1.0";

          # OPTIONAL: Make the tab bar seamless with the background
          # (The theme sets this to #0e090a, which is also not true black)
          inactive_tab_background = "#000000";
          tab_bar_background = "#000000";
        }
        # ==========================================================================
        # General Settings
        # ==========================================================================
        {
          scrollback_pager_history_size = 60;
          allow_remote_control = "socket-only";
          listen_on = "unix:/tmp/kitty";
          shell_integration = "enabled";
          editor = "nvim";
          action_alias = "kitty_scrollback_nvim kitten $HOME/.local/share/nvim/lazy/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py";
          hide_window_decorations = "no";
          # Nerd Fonts v3.2.0
          symbol_map = "U+e000-U+e00a,U+ea60-U+ebeb,U+e0a0-U+e0c8,U+e0ca,U+e0cc-U+e0d7,U+e200-U+e2a9,U+e300-U+e3e3,U+e5fa-U+e6b1,U+e700-U+e7c5,U+ed00-U+efc1,U+f000-U+f2ff,U+f000-U+f2e0,U+f300-U+f372,U+f400-U+f533,U+f0001-U+f1af0 Symbols Nerd Font Mono";
        }

        # ==========================================================================
        # Linux-Specific Settings
        # ==========================================================================
        (lib.mkIf pkgs.stdenv.isLinux {
          linux_display_server = "wayland";
          sync_to_monitor = "no";
        })

        # ==========================================================================
        # macOS-Specific Settings
        # ==========================================================================
        (lib.mkIf pkgs.stdenv.isDarwin {
          macos_option_as_alt = "yes";
          macos_colorspace = "displayp3";
        })
      ];

      keybindings = {
        "ctrl+shift+f" =
          "launch --type=overlay --stdin-source=@screen_scrollback /bin/sh -c \"${pkgs.fzf}/bin/fzf --no-sort --no-mouse --exact -i --tac | kitty +kitten clipboard\"";
        "kitty_mod+s" = "kitty_scrollback_nvim";
        "kitty_mod+e" = "kitty_scrollback_nvim --config ksb_builtin_last_cmd_output";
        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";
        "alt+super+left" = "neighboring_window left";
        "alt+super+right" = "neighboring_window right";
        "alt+super+up" = "neighboring_window up";
        "alt+super+down" = "neighboring_window down";
      };
    };

    home.file.".config/kitty/tab_bar.py".source = ../../dotfiles/kitty/tab_bar.py;
  };
}
