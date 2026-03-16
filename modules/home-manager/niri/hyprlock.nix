# modules/home-manager/niri/hyprlock.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
in
{
  options.local.niri.hyprlock.enable = lib.mkEnableOption "Hyprlock screen locker and Hypridle";

  config = lib.mkIf (cfg.enable && cfg.hyprlock.enable) {
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof hyprlock || hyprlock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "niri msg action power-on-monitors";
        };
        listener = [
          {
            timeout = 260;
            on-timeout = "hyprlock";
          }
          {
            timeout = 300;
            on-timeout = "niri msg action power-off-monitors";
            on-resume = "niri msg action power-on-monitors";
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
          grace = 2;
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
            font_color = "rgb(cdd6f4)";
            check_color = "rgb(c7ff7f)";
            fail_color = "rgb(f38ba8)";
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
            color = "rgb(cdd6f4)";
            font_size = 64;
            font_family = "Maple Mono NF";
            position = "0, 150";
            halign = "center";
            valign = "center";
          }
          {
            text = ''cmd[update:1000] date +"%A, %B %d"'';
            color = "rgb(cdd6f4)";
            font_size = 20;
            font_family = "Maple Mono NF";
            position = "0, 75";
            halign = "center";
            valign = "center";
          }
        ];
      };
    };
  };
}
