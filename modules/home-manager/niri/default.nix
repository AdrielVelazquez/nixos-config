# modules/home-manager/niri/default.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  style = cfg.style;
  wallpaper = ../../../assets/astronaut_oled_fixed.png;
  swayncClient = lib.getExe' pkgs.swaynotificationcenter "swaync-client";
  brightnessctlCmd =
    "brightnessctl"
    + lib.optionalString (cfg.brightnessDevice != null) " --device ${lib.escapeShellArg cfg.brightnessDevice}";
in
{
  imports = [
    ./style.nix
    ./ironbar.nix
    ./swaync.nix
    ./hyprlock.nix
    ./swww.nix
    ./walker.nix
    ./theme.nix
    ./services.nix
    ./kanshi.nix
  ];

  options.local.niri = {
    enable = lib.mkEnableOption "niri Wayland compositor user configuration";
    renderDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/dri/by-path/pci-0000:c5:00.0-render";
      description = "DRM render device for niri to use as primary GPU. Useful for multi-GPU laptops to force the iGPU.";
    };
    ignoreDrmDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/dev/dri/by-path/pci-0000:c4:00.0-card";
      description = "DRM primary (card) device for niri to completely ignore. Use the -card node to block KMS probing and let the dGPU enter D3cold.";
    };
    brightnessDevice = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "amdgpu_bl1";
      description = "Backlight device name for brightnessctl to target explicitly. Useful on hybrid-GPU laptops where the default device may be the wrong GPU.";
    };
    hasDgpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this system has an NVIDIA discrete GPU. Enables the waybar dGPU power-state indicator.";
    };
    useSystemHyprlock = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Use the system-installed hyprlock instead of the nix package. Required on non-NixOS where nix-built PAM binaries can't verify passwords (unix_chkpwd lacks setuid in the nix store).";
    };
    wallpaper = lib.mkOption {
      type = lib.types.path;
      default = wallpaper;
      description = "Path to wallpaper image for swww.";
    };
  };

  config = lib.mkIf cfg.enable {
    local.niri = {
      hyprlock.enable = lib.mkDefault true;
      ironbar.enable = lib.mkDefault true;
      kanshi.enable = lib.mkDefault true;
      services.enable = lib.mkDefault true;
      swaync.enable = lib.mkDefault true;
      swww.enable = lib.mkDefault true;
      theme.enable = lib.mkDefault true;
      walker.enable = lib.mkDefault true;
    };

    programs.niri.settings = {
      spawn-at-startup = [
        { command = [ "kitty" ]; }
      ];

      debug = lib.mkMerge [
        (lib.mkIf (cfg.renderDevice != null) {
          render-drm-device = cfg.renderDevice;
        })
        (lib.mkIf (cfg.ignoreDrmDevice != null) {
          ignore-drm-device = cfg.ignoreDrmDevice;
        })
      ];

      # I use kanshi instead of managing the displays
      # outputs."eDP-1".scale = 1.1;

      input = {
        keyboard.xkb = {
          layout = "us";
        };
        touchpad = {
          tap = true;
          natural-scroll = true;
          click-method = "clickfinger";
        };
      };
      animations = {
        slowdown = 1.0;
        workspace-switch = {
          kind = {
            spring = {
              damping-ratio = 0.8;
              stiffness = 1000;
              epsilon = 0.0001;
            };
          };
        };
        window-open = {
          kind = {
            easing = {
              duration-ms = 200;
              curve = "ease-out-expo";
            };
          };
        };
        window-close = {
          kind = {
            easing = {
              duration-ms = 200;
              curve = "ease-out-expo";
            };
          };
        };
      };

      layout = {
        gaps = 16;
        center-focused-column = "never";
        background-color = style.palette.background;

        preset-column-widths = [
          { proportion = 1.0 / 3.0; }
          { proportion = 1.0 / 2.0; }
          { proportion = 2.0 / 3.0; }
        ];

        default-column-width = {
          proportion = 1.0;
        };
        focus-ring = {
          width = 3;
          active.gradient = {
            from = style.palette.accent;
            to = style.palette.accentAlt;
            angle = 45;
            relative-to = "workspace-view";
          };
          inactive.color = style.palette.inactive;
        };

        border.enable = false;

        shadow = {
          enable = true;
          softness = 30;
          spread = 5;
          offset = {
            x = 0;
            y = 5;
          };
          color = "#0007";
        };
      };

      xwayland-satellite = {
        enable = true;
        path = lib.getExe pkgs.xwayland-satellite-unstable;
      };

      cursor.hide-after-inactive-ms = 3000;

      prefer-no-csd = true;

      screenshot-path = "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png";

      hotkey-overlay.skip-at-startup = true;

      window-rules = [
        {
          geometry-corner-radius =
            let
              r = 12.0;
            in
            {
              top-left = r;
              top-right = r;
              bottom-left = r;
              bottom-right = r;
            };
          clip-to-geometry = true;
        }
      ];

      binds = with config.lib.niri.actions; {
        "Mod+Return".action = spawn "kitty";
        "Mod+D".action = spawn "walker";
        "Super+Alt+L".action = spawn-sh "hyprlock --grace 2";
        "Mod+B".action = spawn "zen-beta";

        "Mod+Shift+Slash".action = show-hotkey-overlay;
        "Mod+O".action = toggle-overview;
        "Mod+Q".action = close-window;

        # Focus
        "Mod+Left".action = focus-column-left;
        "Mod+Down".action = focus-workspace-down;
        "Mod+Up".action = focus-workspace-up;
        "Mod+Right".action = focus-column-right;

        # Move windows
        "Mod+Ctrl+Left".action = move-column-left;
        "Mod+Ctrl+Down".action = move-column-to-workspace-down;
        "Mod+Ctrl+Up".action = move-column-to-workspace-up;
        "Mod+Ctrl+Right".action = move-column-right;
        "Mod+Ctrl+H".action = move-column-left;
        "Mod+Ctrl+J".action = move-window-down;
        "Mod+Ctrl+K".action = move-window-up;
        "Mod+Ctrl+L".action = move-column-right;

        "Mod+Home".action = focus-column-first;
        "Mod+End".action = focus-column-last;
        "Mod+Ctrl+Home".action = move-column-to-first;
        "Mod+Ctrl+End".action = move-column-to-last;

        # Monitor focus/move
        "Mod+Shift+Left".action = focus-monitor-left;
        "Mod+Shift+Down".action = focus-monitor-down;
        "Mod+Shift+Up".action = focus-monitor-up;
        "Mod+Shift+Right".action = focus-monitor-right;

        "Mod+Shift+Ctrl+Left".action = move-column-to-monitor-left;
        "Mod+Shift+Ctrl+Down".action = move-column-to-monitor-down;
        "Mod+Shift+Ctrl+Up".action = move-column-to-monitor-up;
        "Mod+Shift+Ctrl+Right".action = move-column-to-monitor-right;

        # Scroll bindings
        "Mod+WheelScrollDown" = {
          cooldown-ms = 150;
          action = focus-workspace-down;
        };
        "Mod+WheelScrollUp" = {
          cooldown-ms = 150;
          action = focus-workspace-up;
        };
        "Mod+Ctrl+WheelScrollDown" = {
          cooldown-ms = 150;
          action = move-column-to-workspace-down;
        };
        "Mod+Ctrl+WheelScrollUp" = {
          cooldown-ms = 150;
          action = move-column-to-workspace-up;
        };

        "Mod+WheelScrollRight".action = focus-column-right;
        "Mod+WheelScrollLeft".action = focus-column-left;
        "Mod+Ctrl+WheelScrollRight".action = move-column-right;
        "Mod+Ctrl+WheelScrollLeft".action = move-column-left;
        "Mod+Shift+WheelScrollDown".action = focus-column-right;
        "Mod+Shift+WheelScrollUp".action = focus-column-left;

        # Workspace by index
        "Mod+1".action = focus-workspace 1;
        "Mod+2".action = focus-workspace 2;
        "Mod+3".action = focus-workspace 3;
        "Mod+4".action = focus-workspace 4;
        "Mod+5".action = focus-workspace 5;
        "Mod+6".action = focus-workspace 6;
        "Mod+7".action = focus-workspace 7;
        "Mod+8".action = focus-workspace 8;
        "Mod+9".action = focus-workspace 9;

        # Column management
        "Mod+BracketLeft".action = consume-or-expel-window-left;
        "Mod+BracketRight".action = consume-or-expel-window-right;
        "Mod+Comma".action = consume-window-into-column;
        "Mod+Period".action = expel-window-from-column;

        # Sizing
        "Mod+R".action = switch-preset-column-width;
        "Mod+Shift+R".action = switch-preset-window-height;
        "Mod+Ctrl+R".action = reset-window-height;
        "Mod+F".action = maximize-column;
        "Mod+Shift+F".action = fullscreen-window;
        "Mod+C".action = center-column;
        "Mod+Minus".action = set-column-width "-10%";
        "Mod+Equal".action = set-column-width "+10%";
        "Mod+Shift+Minus".action = set-window-height "-10%";
        "Mod+Shift+Equal".action = set-window-height "+10%";

        # Floating / tabbed
        "Mod+V".action = toggle-window-floating;
        "Mod+Shift+V".action = switch-focus-between-floating-and-tiling;
        "Mod+W".action = toggle-column-tabbed-display;

        # Toggle bar
        "Mod+I".action = spawn-sh "ironbar bar main toggle-visible";
        "Mod+N".action = spawn-sh "${swayncClient} --toggle-panel --skip-wait";

        # Clipboard history
        "Mod+Shift+C".action = spawn-sh "cliphist list | walker --dmenu | cliphist decode | wl-copy";

        # Screenshots
        "Print".action.screenshot = [ ];
        "Ctrl+Print".action.screenshot-screen = [ ];
        "Alt+Print".action.screenshot-window = [ ];

        # Screenshot with annotation (region select -> satty editor -> save to Pictures)
        "Mod+Shift+S".action =
          spawn-sh ''grim -g "$(slurp)" - | satty -f - --output-filename ~/Pictures/Screenshots/"Screenshot from $(date +'%Y-%m-%d %H-%M-%S').png" --copy-command wl-copy'';

        # Volume (allow when locked)
        "XF86AudioRaiseVolume" = {
          allow-when-locked = true;
          action = spawn-sh ''
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.0
            vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%.0f", $2*100}')
            notify-send -t 1500 -h int:value:$vol -h string:x-canonical-private-synchronous:volume '󰕾 Volume' "$vol%"
          '';
        };
        "XF86AudioLowerVolume" = {
          allow-when-locked = true;
          action = spawn-sh ''
            wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
            vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ | awk '{printf "%.0f", $2*100}')
            notify-send -t 1500 -h int:value:$vol -h string:x-canonical-private-synchronous:volume '󰕾 Volume' "$vol%"
          '';
        };
        "XF86AudioMute" = {
          allow-when-locked = true;
          action = spawn-sh ''
            wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
            notify-send -t 1500 -h string:x-canonical-private-synchronous:volume '󰝟 Mute toggled'
          '';
        };
        "XF86AudioMicMute" = {
          allow-when-locked = true;
          action = spawn-sh ''
            wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle
            notify-send -t 1500 -h string:x-canonical-private-synchronous:mic '🎤 Mic mute toggled'
          '';
        };

        # Media (allow when locked)
        "XF86AudioPlay" = {
          allow-when-locked = true;
          action = spawn-sh "playerctl play-pause";
        };
        "XF86AudioStop" = {
          allow-when-locked = true;
          action = spawn-sh "playerctl stop";
        };
        "XF86AudioPrev" = {
          allow-when-locked = true;
          action = spawn-sh "playerctl previous";
        };
        "XF86AudioNext" = {
          allow-when-locked = true;
          action = spawn-sh "playerctl next";
        };

        # Brightness (allow when locked)
        "XF86MonBrightnessUp" = {
          allow-when-locked = true;
          action = spawn-sh ''
            ${brightnessctlCmd} set 5%+
            bri=$(${brightnessctlCmd} -m | awk -F, '{print $4}' | tr -d '%')
            notify-send -t 1500 -h int:value:$bri -h string:x-canonical-private-synchronous:brightness '󰃠 Brightness' "$bri%"
          '';
        };
        "XF86MonBrightnessDown" = {
          allow-when-locked = true;
          action = spawn-sh ''
            ${brightnessctlCmd} set 5%-
            bri=$(${brightnessctlCmd} -m | awk -F, '{print $4}' | tr -d '%')
            notify-send -t 1500 -h int:value:$bri -h string:x-canonical-private-synchronous:brightness '󰃠 Brightness' "$bri%"
          '';
        };

        # Session
        "Mod+Escape" = {
          allow-inhibiting = false;
          action = toggle-keyboard-shortcuts-inhibit;
        };
        "Mod+Shift+E".action = quit;
        "Mod+Shift+P".action = power-off-monitors;
      };
    };
  };
}
