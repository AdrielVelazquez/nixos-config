# modules/home-manager/niri.nix
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
  options.local.niri = {
    enable = lib.mkEnableOption "niri Wayland compositor user configuration";
  };

  config = lib.mkIf cfg.enable {
    programs.niri.settings = {
      outputs."*".scale = 1.0;

      input = {
        keyboard.xkb = {
          layout = "us,us";
          variant = ",colemak_dh_ortho";
        };
        touchpad = {
          tap = true;
          natural-scroll = true;
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

        default-column-width = { proportion = 1.0 / 2.0; };

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

      binds =
        with config.lib.niri.actions;
        {
          "Mod+Return".action = spawn "kitty";
          "Mod+D".action = spawn [
            "vicinae"
            "toggle"
          ];
          "Super+Alt+L".action = spawn "swaylock";

          "Mod+Shift+Slash".action = show-hotkey-overlay;
          "Mod+O".action = toggle-overview;
          "Mod+Q".action = close-window;

          # Focus
          "Mod+Left".action = focus-column-left;
          "Mod+Down".action = focus-window-down;
          "Mod+Up".action = focus-window-up;
          "Mod+Right".action = focus-column-right;
          "Mod+H".action = focus-column-left;
          "Mod+J".action = focus-window-down;
          "Mod+K".action = focus-window-up;
          "Mod+L".action = focus-column-right;

          # Move windows
          "Mod+Ctrl+Left".action = move-column-left;
          "Mod+Ctrl+Down".action = move-window-down;
          "Mod+Ctrl+Up".action = move-window-up;
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
          "Mod+Ctrl+Page_Down".action = move-column-to-workspace-down;
          "Mod+Ctrl+Page_Up".action = move-column-to-workspace-up;
          "Mod+Ctrl+U".action = move-column-to-workspace-down;
          "Mod+Ctrl+I".action = move-column-to-workspace-up;

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
          "Mod+Ctrl+1".action = move-column-to-workspace 1;
          "Mod+Ctrl+2".action = move-column-to-workspace 2;
          "Mod+Ctrl+3".action = move-column-to-workspace 3;
          "Mod+Ctrl+4".action = move-column-to-workspace 4;
          "Mod+Ctrl+5".action = move-column-to-workspace 5;
          "Mod+Ctrl+6".action = move-column-to-workspace 6;
          "Mod+Ctrl+7".action = move-column-to-workspace 7;
          "Mod+Ctrl+8".action = move-column-to-workspace 8;
          "Mod+Ctrl+9".action = move-column-to-workspace 9;

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
          "Mod+Shift+C".action = spawn-sh "cliphist list | vicinae dmenu --placeholder 'Clipboard history' | cliphist decode | wl-copy";

          # Keyboard layout
          "Mod+Space".action = switch-layout "next";

          # Screenshots
          "Print".action = screenshot;
          "Ctrl+Print".action = screenshot-screen;

          # Volume (allow when locked)
          "XF86AudioRaiseVolume" = {
            allow-when-locked = true;
            action = spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1+ -l 1.0";
          };
          "XF86AudioLowerVolume" = {
            allow-when-locked = true;
            action = spawn-sh "wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.1-";
          };
          "XF86AudioMute" = {
            allow-when-locked = true;
            action = spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle";
          };
          "XF86AudioMicMute" = {
            allow-when-locked = true;
            action = spawn-sh "wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle";
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
            action = spawn [
              "brightnessctl"
              "--class=backlight"
              "set"
              "+10%"
            ];
          };
          "XF86MonBrightnessDown" = {
            allow-when-locked = true;
            action = spawn [
              "brightnessctl"
              "--class=backlight"
              "set"
              "10%-"
            ];
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
          modules-right = [
            "power-profiles-daemon"
            "niri/language"
            "pulseaudio"
            "network"
            "battery"
            "clock"
            "tray"
          ];

          "niri/workspaces" = {
            format = "{icon}";
            format-icons = {
              active = "";
              default = "";
            };
          };

          "niri/window" = {
            format = "{}";
            max-length = 50;
          };

          "niri/language" = {
            format = "{}";
            format-en = "US";
            format-en-colemak-dh-ortho = "CM";
            on-click = "niri msg action switch-layout next";
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
            format-icons = [
              ""
              ""
              ""
              ""
              ""
            ];
          };

          network = {
            format-wifi = " {signalStrength}%";
            format-ethernet = " {ifname}";
            format-disconnected = "⚠ Disconnected";
            tooltip-format = "{ifname}: {ipaddr}/{cidr}";
            on-click = "iwgtk";
          };

          pulseaudio = {
            format = "{icon} {volume}%";
            format-muted = " Muted";
            format-icons = {
              default = [
                ""
                ""
                ""
              ];
            };
            on-click = "pwvucontrol";
          };

          power-profiles-daemon = {
            format = "{icon}";
            format-icons = {
              default = "";
              performance = "";
              balanced = "";
              power-saver = "";
            };
            tooltip-format = "Power profile: {profile}";
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
          background: #000000;
          color: #cdd6f4;
        }

        #workspaces button {
          padding: 0 8px;
          color: #6c7086;
          border-bottom: 3px solid transparent;
        }

        #workspaces button.active {
          color: #5a9cbf;
          border-bottom: 3px solid #5a9cbf;
        }

        #clock, #battery, #network, #pulseaudio, #power-profiles-daemon, #language, #tray {
          padding: 0 12px;
        }

        #battery.warning {
          color: #f9e2af;
        }

        #battery.critical {
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
            timeout = 300;
            on-timeout = "swaylock";
          }
          {
            timeout = 600;
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
        effect-blur = "7x5";
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

    home.packages = with pkgs; [
      swww
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
