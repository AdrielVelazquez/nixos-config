# modules/home-manager/niri.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  wallpaper = ../../assets/astronaut_oled_fixed.png;
in
{
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
      example = "/dev/dri/by-path/pci-0000:c4:00.0-render";
      description = "DRM device for niri to completely ignore (won't even open it). Useful to let a dGPU enter D3cold.";
    };
    hasDgpu = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this system has an NVIDIA discrete GPU. Enables the waybar dGPU power-state indicator.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.niri.settings = {
      debug = lib.mkMerge [
        (lib.mkIf (cfg.renderDevice != null) {
          render-drm-device = cfg.renderDevice;
        })
        (lib.mkIf (cfg.ignoreDrmDevice != null) {
          ignore-drm-device = cfg.ignoreDrmDevice;
        })
      ];

      outputs."eDP-1".scale = 1.1;

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

      layout = {
        gaps = 16;
        center-focused-column = "never";
        background-color = "#000000";

        preset-column-widths = [
          { proportion = 1.0 / 3.0; }
          { proportion = 1.0 / 2.0; }
          { proportion = 2.0 / 3.0; }
        ];

        default-column-width = {
          proportion = 1.0;
        };

        focus-ring = {
          width = 2;
          active.color = "#5a9cbf";
          inactive.color = "#383838";
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
        "Mod+D".action = spawn [
          "vicinae"
          "toggle"
        ];
        "Super+Alt+L".action = spawn "swaylock";
        "Mod+B".action = spawn "zen-beta";

        "Mod+Shift+Slash".action = show-hotkey-overlay;
        "Mod+O".action = toggle-overview;
        "Mod+Q".action = close-window;

        # Focus
        "Mod+Left".action = focus-column-left;
        "Mod+Down".action = focus-workspace-down;
        "Mod+Up".action = focus-workspace-up;
        "Mod+Right".action = focus-column-right;
        "Mod+H".action = focus-column-left;
        "Mod+J".action = focus-window-down;
        "Mod+K".action = focus-window-up;
        "Mod+L".action = focus-column-right;

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
        "Mod+Shift+H".action = focus-monitor-left;
        "Mod+Shift+J".action = focus-monitor-down;
        "Mod+Shift+K".action = focus-monitor-up;
        "Mod+Shift+L".action = focus-monitor-right;

        "Mod+Shift+Ctrl+Left".action = move-column-to-monitor-left;
        "Mod+Shift+Ctrl+Down".action = move-column-to-monitor-down;
        "Mod+Shift+Ctrl+Up".action = move-column-to-monitor-up;
        "Mod+Shift+Ctrl+Right".action = move-column-to-monitor-right;
        "Mod+Shift+Ctrl+H".action = move-column-to-monitor-left;
        "Mod+Shift+Ctrl+J".action = move-column-to-monitor-down;
        "Mod+Shift+Ctrl+K".action = move-column-to-monitor-up;
        "Mod+Shift+Ctrl+L".action = move-column-to-monitor-right;

        # Workspace navigation
        "Mod+Page_Down".action = focus-workspace-down;
        "Mod+Page_Up".action = focus-workspace-up;
        "Mod+U".action = focus-workspace-down;
        "Mod+I".action = focus-workspace-up;

        "Mod+Shift+Page_Down".action = move-workspace-down;
        "Mod+Shift+Page_Up".action = move-workspace-up;
        "Mod+Shift+U".action = move-workspace-down;
        "Mod+Shift+I".action = move-workspace-up;

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

        # Clipboard history
        "Mod+Shift+C".action =
          spawn-sh "cliphist list | vicinae dmenu --placeholder 'Clipboard history' | cliphist decode | wl-copy";

        # Keyboard layout

        # Volume (allow when locked) — routed through SwayOSD for visual feedback
        "XF86AudioRaiseVolume" = {
          allow-when-locked = true;
          action = spawn [ "swayosd-client" "--output-volume" "raise" ];
        };
        "XF86AudioLowerVolume" = {
          allow-when-locked = true;
          action = spawn [ "swayosd-client" "--output-volume" "lower" ];
        };
        "XF86AudioMute" = {
          allow-when-locked = true;
          action = spawn [ "swayosd-client" "--output-volume" "mute-toggle" ];
        };
        "XF86AudioMicMute" = {
          allow-when-locked = true;
          action = spawn [ "swayosd-client" "--input-volume" "mute-toggle" ];
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

        # Brightness (allow when locked) — routed through SwayOSD for visual feedback
        "XF86MonBrightnessUp" = {
          allow-when-locked = true;
          action = spawn [ "swayosd-client" "--brightness" "raise" ];
        };
        "XF86MonBrightnessDown" = {
          allow-when-locked = true;
          action = spawn [ "swayosd-client" "--brightness" "lower" ];
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

    # -- Waybar --
    programs.waybar = {
      enable = true;
      systemd.enable = true;

      settings = [
        {
          layer = "top";
          position = "top";
          height = 36;

          modules-left = [ "niri/workspaces" ];
          modules-center = [ "niri/window" ];
          modules-right = lib.optional cfg.hasDgpu "custom/nvidia" ++ [
            "power-profiles-daemon"
            "network"
            "pulseaudio"
            "battery"
            "clock"
            "tray"
          ];

          "niri/workspaces" = {
            format = "{index}";
          };

          "niri/window" = {
            format = "{}";
            max-length = 50;
          };

          clock = {
            format = "{:%H:%M}";
            format-alt = "{:%Y-%m-%d %H:%M}";
            tooltip-format = "{:%A, %B %d, %Y}";
          };

          battery = {
            states = {
              warning = 30;
              critical = 15;
            };
            format = "{icon} {capacity}%";
            format-charging = " {capacity}%";
            tooltip-format = "{timeTo}";
            format-icons = [
              ""
              ""
              ""
              ""
              ""
            ];
          };

          network = {
            format-wifi = "{icon} {signalStrength}%";
            format-ethernet = " {ifname}";
            format-disconnected = "⚠ Disconnected";
            format-icons = [
              "󰤟"
              "󰤢"
              "󰤥"
              "<span color='#a6e3a1'>󰤨</span>"
            ];
            tooltip-format = "{ifname}: {ipaddr}/{cidr}";
            on-click = "iwgtk";
          };

          pulseaudio = {
            format = "{icon}";
            format-muted = "󰝟";
            tooltip-format = "{volume}%";
            format-icons = {
              default = [
                "󰕿"
                "󰖀"
                "󰕾"
              ];
            };
            on-click = "pwvucontrol";
          };

          power-profiles-daemon = {
            format = "{icon}";
            format-icons = {
              default = "";
              performance = "";
              balanced = "";
              power-saver = "";
            };
            tooltip-format = "Power profile: {profile}";
          };

          "custom/nvidia" = lib.mkIf cfg.hasDgpu {
            exec = pkgs.writeShellScript "nvidia-status" ''
              state=$(cat /sys/bus/pci/devices/0000:c4:00.0/power_state)
              case "$state" in
                D3cold) echo '{"text": "󰍹", "tooltip": "NVIDIA dGPU: off (D3cold)", "class": "off"}' ;;
                D3hot)  echo '{"text": "󰍹", "tooltip": "NVIDIA dGPU: idle (D3hot)", "class": "idle"}' ;;
                *)      echo '{"text": "󰍹", "tooltip": "NVIDIA dGPU: active ('"$state"')", "class": "active"}' ;;
              esac
            '';
            return-type = "json";
            interval = 300;
          };

          tray = {
            spacing = 10;
          };
        }
      ];

      style = ''
        * {
          font-family: "Maple Mono NF", monospace;
          font-size: 14px;
          min-height: 0;
        }

        window#waybar {
          background: transparent;
          color: #cdd6f4;
        }

        .modules-left,
        .modules-center,
        .modules-right {
          background: rgba(0, 0, 0, 0.7);
          border-radius: 10px;
          margin: 4px 4px;
          padding: 0 4px;
        }

        #workspaces button {
          padding: 0 8px;
          color: #6c7086;
          border-radius: 8px;
          margin: 2px;
        }

        #workspaces button.active {
          color: #5a9cbf;
          background: rgba(90, 156, 191, 0.2);
        }

        #window {
          padding: 0 16px;
        }

        #clock, #battery, #network, #pulseaudio, #power-profiles-daemon, #language, #tray, #custom-nvidia {
          padding: 0 10px;
        }

        #battery.warning {
          color: #f9e2af;
        }

        #battery.critical {
          color: #f38ba8;
        }

        #custom-nvidia.off {
          color: #6c7086;
        }

        #custom-nvidia.idle {
          color: #f9e2af;
        }

        #custom-nvidia.active {
          color: #f38ba8;
        }
      '';
    };

    # -- Vicinae launcher --
    programs.vicinae = {
      enable = true;
      useLayerShell = true;
      systemd.enable = true;
      settings = {
        launcher_window = {
          opacity = 1.0;
        };
        theme = {
          dark.name = "Default Dark";
        };
      };
    };

    # -- Notification center --
    services.swaync = {
      enable = true;
    };

    # -- Idle management --
    services.hypridle = {
      enable = true;
      settings = {
        general = {
          lock_cmd = "pidof swaylock || swaylock";
          before_sleep_cmd = "loginctl lock-session";
          after_sleep_cmd = "niri msg action power-on-monitors";
        };
        listener = [
          {
            timeout = 260;
            on-timeout = "swaylock";
          }
          {
            timeout = 300;
            on-timeout = "niri msg action power-off-monitors";
            on-resume = "niri msg action power-on-monitors";
          }
        ];
      };
    };

    # -- Lock screen --
    programs.swaylock = {
      enable = true;
      package = pkgs.swaylock-effects;
      settings = {
        clock = true;
        indicator = true;
        indicator-radius = 100;
        indicator-thickness = 7;
        color = "000000";
        effect-vignette = "0.5:0.5";
        ring-color = "7fc8ff";
        key-hl-color = "c7ff7f";
        line-color = "00000000";
        inside-color = "00000088";
        separator-color = "00000000";
        grace = 2;
        fade-in = 0.2;
      };
    };

    # -- Volume / brightness OSD --
    systemd.user.services.swayosd = {
      Unit = {
        Description = "SwayOSD on-screen display server";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.swayosd}/bin/swayosd-server";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # -- Wallpaper daemon --
    systemd.user.services.swww = {
      Unit = {
        Description = "swww wallpaper daemon";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.swww}/bin/swww-daemon";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.swww-wallpaper = {
      Unit = {
        Description = "Set wallpaper via swww";
        After = [ "swww.service" ];
        Requires = [ "swww.service" ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${pkgs.swww}/bin/swww img ${wallpaper}";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    home.packages = with pkgs; [
      swww
      swayosd
      grim
      slurp
      brightnessctl
      playerctl
      yazi
      imv
      mpv
      cliphist
      wlsunset
      file-roller
      wf-recorder
      nwg-displays
      iwgtk
      overskride
      pwvucontrol
    ];

    # -- GTK dark theme + cursor --
    gtk = {
      enable = true;
      theme = {
        name = "adw-gtk3-dark";
        package = pkgs.adw-gtk3;
      };
      iconTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
      };
    };

    home.pointerCursor = {
      name = "Adwaita";
      package = pkgs.adwaita-icon-theme;
      size = 24;
      gtk.enable = true;
    };

    dconf.settings."org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
    };

    # -- USB auto-mount with tray icon --
    services.udiskie = {
      enable = true;
      tray = "auto";
    };

    # -- Clipboard history watcher --
    systemd.user.services.cliphist = {
      Unit = {
        Description = "Clipboard history watcher";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.bash}/bin/bash -c '${pkgs.wl-clipboard}/bin/wl-paste --watch ${pkgs.cliphist}/bin/cliphist store'";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # -- Night light (color temperature shift) --
    systemd.user.services.wlsunset = {
      Unit = {
        Description = "Day/night color temperature adjustment";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.wlsunset}/bin/wlsunset -t 3500 -T 6500";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };
  };
}
