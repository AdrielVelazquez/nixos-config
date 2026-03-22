# modules/home-manager/niri/hyprlock.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  fontFamily = cfg.style.font.family;
  toRgb = color: "rgb(${lib.removePrefix "#" color})";
in
{
  options.local.niri.hyprlock = {
    enable = lib.mkEnableOption "Hyprlock screen locker and Hypridle";
    suspendTimeoutSeconds = lib.mkOption {
      type = lib.types.nullOr lib.types.int;
      default = 600;
      example = 1200;
      description = "Suspend-then-hibernate after this many seconds of inactivity. Set to null to disable idle sleep.";
    };
  };

  config = lib.mkIf (cfg.enable && cfg.hyprlock.enable) {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock --grace 2";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "niri msg action power-on-monitors";
        };
        listener =
          [
            {
              timeout = 260;
              on-timeout = "pidof hyprlock || hyprlock --grace 2";
            }
            {
              timeout = 300;
              on-timeout = "niri msg action power-off-monitors";
              on-resume = "niri msg action power-on-monitors";
            }
          ]
          ++ lib.optionals (cfg.hyprlock.suspendTimeoutSeconds != null) [
            {
              timeout = cfg.hyprlock.suspendTimeoutSeconds;
              on-timeout = "${pkgs.systemd}/bin/systemctl suspend-then-hibernate";
            }
          ];
      };
    };

    programs.hyprlock = {
      enable = true;
      package =
        if cfg.useSystemHyprlock then
          pkgs.runCommand "hyprlock-system" { } ''
            mkdir -p $out/bin
            ln -s /usr/bin/hyprlock $out/bin/hyprlock
          ''
        else
          pkgs.hyprlock;
      settings = {
        general = {
          hide_cursor = true;
        };
        background = [
          {
            path = "screenshot";
            blur_passes = 3;
            blur_size = 5;
            vibrancy = 0.2;
          }
        ];
        input-field = [
          {
            size = "250, 60";
            outline_thickness = 7;
            outer_color = "rgb(7fc8ff)";
            inner_color = "rgba(0, 0, 0, 0.53)";
            font_color = toRgb palette.foreground;
            check_color = toRgb palette.success;
            fail_color = toRgb palette.danger;
            fade_on_empty = true;
            placeholder_text = "";
            dots_center = true;
            dots_spacing = 0.3;
            rounding = -1;
            position = "0, -80";
            halign = "center";
            valign = "center";
          }
        ];
        label = [
          {
            text = ''cmd[update:1000] date +"%H:%M"'';
            color = toRgb palette.foreground;
            font_size = 64;
            font_family = fontFamily;
            position = "0, 150";
            halign = "center";
            valign = "center";
          }
          {
            text = ''cmd[update:1000] date +"%A, %B %d"'';
            color = toRgb palette.foreground;
            font_size = 20;
            font_family = fontFamily;
            position = "0, 75";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
