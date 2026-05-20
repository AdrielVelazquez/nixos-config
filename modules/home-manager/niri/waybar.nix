# modules/home-manager/niri/waybar.nix
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
  scripts = import ./scripts.nix { inherit lib config pkgs; };
  waybarXdgDataDirs = lib.concatStringsSep ":" [
    "/etc/profiles/per-user/${config.home.username}/share"
    "/run/current-system/sw/share"
    "${pkgs.papirus-icon-theme}/share"
    "${pkgs.adwaita-icon-theme}/share"
    "${pkgs.hicolor-icon-theme}/share"
  ];
in
{
  options.local.niri.waybar.enable = lib.mkEnableOption "Waybar status bar";

  config = lib.mkIf (cfg.enable && cfg.waybar.enable) {
    programs.waybar = {
      enable = true;
      systemd.enable = true;

      settings = {
        mainBar = {
          name = "main";
          layer = "top";
          position = "top";
          height = 44;
          mode = "dock";
          exclusive = true;
          on-sigusr1 = "toggle";
          on-sigusr2 = "reload";

          modules-left = [ "clock" ];
          modules-center = [ "niri/workspaces" ];
          modules-right = lib.optional (cfg.dgpuPciPath != null) "custom/nvidia" ++ [
            "power-profiles-daemon"
            "network"
            "bluetooth"
            "pulseaudio"
            "custom/sunsetr"
            "custom/battery"
            "custom/notifications"
            "tray"
          ];

          "niri/workspaces" = {
            all-outputs = false;
            format = "{index}";
          };

          clock = {
            interval = 60;
            format = "{:%a %b %d  %H:%M}";
            tooltip-format = "<tt><small>{calendar}</small></tt>";
          };

          "custom/nvidia" = {
            exec = scripts.nvidiaWaybarStatus;
            return-type = "json";
            interval = 30;
            signal = 1;
            format = "{text}";
            on-click = scripts.nvidiaWaybarDetails;
          };

          power-profiles-daemon = {
            format = "{icon}";
            tooltip-format = "Power profile: {profile}\nDriver: {driver}";
            format-icons = {
              default = "";
              performance = "";
              balanced = "";
              power-saver = "";
            };
          };

          network = {
            interface = "wl*";
            interval = 30;
            format-wifi = "󰤨";
            format-linked = "󰤢";
            format-disconnected = "󰤮";
            format-disabled = "󰤭";
            tooltip-format-wifi = "{essid} ({signalStrength}%)\n{ipaddr}/{cidr}";
            tooltip-format-linked = "{ifname}: linked";
            tooltip-format-disconnected = "Wi-Fi disconnected";
            tooltip-format-disabled = "Wi-Fi disabled";
            on-click = scripts.openNetworkSettings;
          };

          bluetooth = {
            format-disabled = "";
            format-off = "";
            format-on = "";
            format-connected = "";
            format-connected-battery = "";
            format-no-controller = "";
            tooltip-format-disabled = "Bluetooth disabled";
            tooltip-format-off = "Bluetooth off";
            tooltip-format-on = "{controller_alias}";
            tooltip-format-connected = "{controller_alias}\n{num_connections} connected\n{device_enumerate}";
            tooltip-format-enumerate-connected = "{device_alias}";
            tooltip-format-enumerate-connected-battery = "{device_alias} ({device_battery_percentage}%)";
            on-click = scripts.openBluetoothSettings;
          };

          pulseaudio = {
            format = "{icon}";
            format-bluetooth = "{icon}";
            format-muted = "󰝟";
            tooltip-format = "{volume}%";
            scroll-step = 5;
            max-volume = 150;
            format-icons = {
              default = [
                "󰕿"
                "󰖀"
                "󰕾"
              ];
            };
            on-click = lib.getExe pkgs.pwvucontrol;
          };

          "custom/sunsetr" = {
            exec = scripts.sunsetrWaybarStatus;
            return-type = "json";
            interval = 30;
            signal = 2;
            format = "{text}";
            on-click = scripts.sunsetrToggle;
          };

          "custom/battery" = {
            exec = scripts.batteryWaybarStatus;
            return-type = "json";
            interval = 120;
            format = "{text}";
          };

          "custom/notifications" = {
            exec = scripts.notificationsWaybarStatus;
            return-type = "json";
            interval = 60;
            signal = 3;
            format = "{text}";
            on-click = scripts.notificationsDismissAll;
            on-click-middle = scripts.notificationsRestore;
            on-click-right = scripts.notificationsToggleDnd;
          };

          tray = {
            icon-size = 18;
            spacing = 8;
            show-passive-items = false;
          };
        };
      };

      style = ''
        @define-color bg alpha(${palette.background}, 0.70);
        @define-color fg ${palette.foreground};
        @define-color accent ${palette.accent};
        @define-color muted ${palette.muted};
        @define-color warning ${palette.warning};
        @define-color danger ${palette.danger};
        @define-color success ${palette.success};

        * {
          border: none;
          box-shadow: none;
          font-family: "${fontFamily}", monospace;
          font-size: 14px;
          min-height: 0;
        }

        window#waybar {
          background: transparent;
          color: @fg;
        }

        window#waybar.hidden {
          opacity: 0.02;
        }

        .modules-left,
        .modules-center,
        .modules-right {
          background: @bg;
          border-radius: 10px;
          margin: 4px;
          padding: 0 4px;
        }

        #clock,
        #power-profiles-daemon,
        #network,
        #bluetooth,
        #pulseaudio,
        #custom-sunsetr,
        #custom-battery,
        #custom-notifications,
        #custom-nvidia {
          color: @fg;
          padding: 0 10px;
          transition: color 160ms ease, margin 160ms ease;
        }

        #tray {
          padding: 0 8px;
        }

        #tray > .active,
        #tray > .passive,
        #tray > .needs-attention {
          padding: 0 3px;
        }

        #workspaces button {
          background: transparent;
          border-radius: 8px;
          color: @muted;
          margin: 2px;
          padding: 0 8px;
          transition: background 160ms ease, color 160ms ease, margin 160ms ease;
        }

        #workspaces button.focused {
          background: alpha(@accent, 0.20);
          color: @accent;
        }

        #workspaces button.active {
          color: @fg;
        }

        #workspaces button.urgent {
          background: alpha(@danger, 0.24);
          color: @danger;
        }

        #workspaces button:hover,
        #clock:hover,
        #power-profiles-daemon:hover,
        #network:hover,
        #bluetooth:hover,
        #pulseaudio:hover,
        #custom-sunsetr:hover,
        #custom-battery:hover,
        #custom-notifications:hover,
        #custom-nvidia:hover {
          background: alpha(@accent, 0.14);
          border-radius: 8px;
        }

        #network.disconnected,
        #network.disabled,
        #bluetooth.disabled,
        #bluetooth.off,
        #custom-sunsetr.off,
        #custom-notifications.dnd,
        #custom-notifications.clear,
        #custom-nvidia.off {
          color: @muted;
        }

        #bluetooth.connected,
        #custom-sunsetr.on,
        #custom-notifications.unread {
          color: @accent;
        }

        #custom-battery.charging,
        #custom-battery.full,
        #custom-battery.plugged {
          color: @success;
        }

        #custom-nvidia.idle,
        #custom-battery.warning {
          color: @warning;
        }

        #custom-nvidia.active,
        #custom-battery.critical,
        #custom-notifications.unknown {
          color: @danger;
        }

        tooltip {
          background: alpha(${palette.background}, 0.96);
          border: 1px solid alpha(@accent, 0.28);
          border-radius: 10px;
          color: @fg;
        }

        tooltip label {
          color: @fg;
          padding: 6px;
        }
      '';
    };

    systemd.user.services.waybar.Service.Environment = [
      "__EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json"
      "GDK_BACKEND=wayland"
      "GSK_RENDERER=cairo"
      "LIBGL_ALWAYS_SOFTWARE=1"
      "XDG_DATA_DIRS=${waybarXdgDataDirs}"
    ];
  };
}
