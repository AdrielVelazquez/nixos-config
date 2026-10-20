# modules/home-manager/kitty.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.kitty;
in
{
  options.local.kitty = {
    enable = lib.mkEnableOption "Enables Kitty Terminal Settings";

    enableGpuRecovery = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable defensive settings for compositors that invalidate GPU contexts on sleep/lock (e.g. COSMIC)";
    };
  };

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
        {
          font_family = "Maple Mono NF";
          bold_font = "auto";
          italic_font = "auto";
          bold_italic_font = "auto";
          font_size = "11.0";
          font_features = "MapleMono-NF-Regular -calt +zero";
          auto_reload_config = "-1";
        }

        {
          # Tabs, splits and sessions live in tuios.
          tab_bar_style = "hidden";
        }

        # OLED: force pure black, no transparency
        {
          background = "#000000";
          background_opacity = "1.0";
        }

        {
          scrollback_pager_history_size = 60;
          allow_remote_control = "socket-only";
          listen_on = "unix:/tmp/kitty";
          shell_integration = "enabled";
          editor = "nvim";
          action_alias = "kitty_scrollback_nvim kitten $HOME/.local/share/nvim/site/pack/core/opt/kitty-scrollback.nvim/python/kitty_scrollback_nvim.py";
          hide_window_decorations = "no";
          symbol_map = "U+e000-U+e00a,U+ea60-U+ebeb,U+e0a0-U+e0c8,U+e0ca,U+e0cc-U+e0d7,U+e200-U+e2a9,U+e300-U+e3e3,U+e5fa-U+e6b1,U+e700-U+e7c5,U+ed00-U+efc1,U+f000-U+f2ff,U+f000-U+f2e0,U+f300-U+f372,U+f400-U+f533,U+f0001-U+f1af0 Symbols Nerd Font Mono";
        }

        (lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
          linux_display_server = "wayland";
          sync_to_monitor = "no";
        })

        (lib.mkIf cfg.enableGpuRecovery {
          wayland_enable_ime = "no";
          confirm_os_window_close = "-1";
          close_on_child_death = "no";
        })

        (lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
          macos_option_as_alt = "yes";
          macos_colorspace = "displayp3";
        })
      ];

      keybindings = {
        "ctrl+shift+f" =
          "launch --type=overlay --stdin-source=@screen_scrollback /bin/sh -c \"${pkgs.fzf}/bin/fzf --no-sort --no-mouse --exact -i --tac | kitty +kitten clipboard\"";
        # Kitty can only see tuios's own screen; tuios binds this key to the
        # focused pane's scrollback instead.
        "kitty_mod+s" = "no_op";
        # Unbind the shortcut instead of restoring Kitty's default URL hints.
        "kitty_mod+e" = "no_op";
        "ctrl+shift+c" = "copy_to_clipboard";
        "ctrl+shift+v" = "paste_from_clipboard";
        # Pass these keys through to tuios, which binds them to new/close pane.
        "ctrl+shift+t" = "no_op";
        "ctrl+shift+q" = "no_op";
        "ctrl+tab" = "no_op";
        "ctrl+shift+tab" = "no_op";
      }
      # Kitty's default Ctrl+Alt+1..9 tab jumps; tuios uses them for sessions.
      // lib.listToAttrs (map (n: lib.nameValuePair "ctrl+alt+${toString n}" "no_op") (lib.range 1 9));
    };
  };
}
