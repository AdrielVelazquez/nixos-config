# modules/home-manager/noctalia.nix
#
# Noctalia v5 shell integration. Disabled by default so it can be opted into
# per-user as a fuller shell profile without removing the underlying Niri stack.
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.noctalia;
  niriCfg = config.local.niri;
  niriStyle = niriCfg.style;
  wallpaper = if cfg.wallpaper != null then cfg.wallpaper else niriCfg.wallpaper;
in
{
  imports = [
    inputs.noctalia.homeModules.default
  ];

  options.local.noctalia = {
    enable = lib.mkEnableOption "Noctalia v5 Wayland shell";

    replaceNiriCompanions = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Disable overlapping Waybar, Mako, and swaybg services when Noctalia is enabled.";
    };

    wallpaper = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Wallpaper path for Noctalia. Defaults to local.niri.wallpaper.";
    };

    uiScale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Noctalia shell UI scale. Output DPI/scale remains managed by Niri and Kanshi.";
    };

    barScale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Noctalia bar content scale.";
    };

    notificationScale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Noctalia notification scale.";
    };

    osdScale = lib.mkOption {
      type = lib.types.float;
      default = 1.0;
      description = "Noctalia OSD scale.";
    };

    builtinTheme = lib.mkOption {
      type = lib.types.str;
      default = "Catppuccin";
      description = "Noctalia built-in theme palette.";
    };
  };

  config = lib.mkIf cfg.enable {
    local.niri = lib.mkIf (niriCfg.enable && cfg.replaceNiriCompanions) {
      waybar.enable = lib.mkOverride 900 false;
      mako.enable = lib.mkOverride 900 false;
      wallpaperService.enable = lib.mkOverride 900 false;
    };

    programs.noctalia = {
      enable = true;
      systemd.enable = true;
      settings = {
        shell = {
          ui_scale = cfg.uiScale;
          corner_radius_scale = 1.0;
          font_family = niriStyle.font.family;
          time_format = "{:%H:%M}";
          date_format = "%A, %x";
          offline_mode = true;
          telemetry_enabled = false;
          niri_overview_type_to_launch_enabled = true;
          polkit_agent = false;
          password_style = "default";
          settings_show_advanced = true;
          middle_click_opens_widget_settings = true;
          show_location = false;
          clipboard_enabled = true;
          clipboard_history_max_entries = 100;
          clipboard_auto_paste = "auto";
          clipboard_image_action_command = "${lib.getExe pkgs.satty} -f -";

          animation = {
            enabled = true;
            speed = 1.0;
          };

          shadow = {
            blur = 12;
            offset_x = 2;
            offset_y = 2;
            alpha = 0.55;
          };

          panel = {
            background_blur = true;
            transparency_mode = "solid";
            borders = true;
            shadow = true;
            launcher_placement = "centered";
            clipboard_placement = "centered";
            control_center_placement = "attached";
            wallpaper_placement = "attached";
            session_placement = "attached";
            open_near_click_control_center = false;
            open_near_click_launcher = false;
            open_near_click_clipboard = false;
            open_near_click_wallpaper = false;
            open_near_click_session = false;
          };

          mpris.blacklist = [ ];
        };

        wallpaper = {
          enabled = true;
          fill_mode = "crop";
          fill_color = niriStyle.palette.background;
          transition = [
            "fade"
            "wipe"
            "disc"
            "stripes"
            "zoom"
            "honeycomb"
          ];
          transition_duration = 1500;
          edge_smoothness = 0.3;
          directory = "~/Pictures/Wallpapers";
          directory_light = "";
          directory_dark = "";

          default.path = toString wallpaper;

          automation = {
            enabled = false;
            interval_minutes = 0;
            order = "random";
            recursive = true;
          };
        };

        theme = {
          mode = "dark";
          source = "builtin";
          builtin = cfg.builtinTheme;

          templates = {
            enable_builtin_templates = true;
            builtin_ids = [ ];
            enable_community_templates = false;
            community_ids = [ ];
          };
        };

        backdrop = {
          enabled = true;
          blur_intensity = 0.35;
          tint_intensity = 0.25;
        };

        notification = {
          enable_daemon = true;
          layer = "top";
          scale = cfg.notificationScale;
          background_opacity = 0.97;
          offset_x = 20;
          offset_y = 8;
        };

        osd = {
          position = "top_right";
          orientation = "horizontal";
          scale = cfg.osdScale;
          offset_x = 20;
          offset_y = 8;
          lock_keys = true;
          keyboard_layout = true;
        };

        system.monitor = {
          enabled = true;
          cpu_poll_seconds = 2.0;
          gpu_poll_seconds = 5.0;
          memory_poll_seconds = 2.0;
          network_poll_seconds = 3.0;
          disk_poll_seconds = 10.0;
        };

        weather = {
          enabled = false;
          auto_locate = false;
          address = "";
          refresh_minutes = 30;
          unit = "fahrenheit";
        };

        audio = {
          enable_overdrive = true;
          enable_sounds = false;
          sound_volume = 0.5;
          volume_change_sound = "";
          notification_sound = "";
        };

        brightness = {
          enable_ddcutil = false;
        };

        nightlight = {
          enabled = false;
          force = false;
          use_weather_location = false;
          temperature_day = 6500;
          temperature_night = 4000;
        };

        idle.behavior = {
          lock = {
            timeout = 600;
            command = "noctalia:screen-lock";
            enabled = false;
          };

          screen-off = {
            timeout = 660;
            command = "noctalia:dpms-off";
            resume_command = "noctalia:dpms-on";
            enabled = false;
          };
        };

        keybinds = {
          validate = [
            "return"
            "kp_enter"
          ];
          cancel = [ "escape" ];
          left = [ "left" ];
          right = [ "right" ];
          up = [ "up" ];
          down = [ "down" ];
        };

        bar.main = {
          position = "top";
          thickness = 44;
          background_opacity = 0.86;
          radius = 10;
          margin_h = 8;
          margin_v = 4;
          padding = 10;
          widget_spacing = 6;
          scale = cfg.barScale;
          shadow = true;
          auto_hide = false;
          reserve_space = true;
          capsule = true;
          capsule_radius = 8.0;
          capsule_fill = "surface_variant";
          capsule_opacity = 0.9;
          capsule_foreground = "on_surface";
          start = [
            "launcher"
            "wallpaper"
            "workspaces"
          ];
          center = [ "clock" ];
          end = [
            "media"
            "tray"
            "notifications"
            "clipboard"
            "network"
            "bluetooth"
            "volume"
            "brightness"
            "battery"
            "control-center"
            "session"
          ];
        };

        dock = {
          enabled = false;
          position = "bottom";
          icon_size = 48;
          padding = 8;
          item_spacing = 6;
          background_opacity = 0.88;
          radius = 16;
          margin_h = 0;
          margin_v = 8;
          shadow = true;
          show_running = true;
          auto_hide = false;
          reserve_space = false;
          show_dots = false;
          show_instance_count = true;
          launcher_position = "none";
          launcher_icon = "grid-dots";
          active_monitor_only = false;
          pinned = [ ];
        };

        desktop_widgets.enabled = false;

        control_center.shortcuts = [
          { type = "wifi"; }
          { type = "bluetooth"; }
          { type = "nightlight"; }
          { type = "notification"; }
          { type = "wallpaper"; }
          { type = "power_profile"; }
        ];

        hooks.battery_low_percent_threshold = 15;

        widget = {
          clock = {
            format = "{:%a %b %d  %H:%M}";
            vertical_format = "{:%H\\n%M}";
            scale = 1.0;
            font_weight = 700;
          };

          notifications.hide_when_no_unread = false;
        };
      };
    };
  };
}
