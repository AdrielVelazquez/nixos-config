# modules/home-manager/niri/ironbar.nix
{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  fontFamily = cfg.style.font.family;
  tooltipCss = import ./tooltip-css.nix { inherit palette; };
  trayFallbackIconThemeName = "Papirus-Dark-Fallback";
  trayFallbackIconTheme = pkgs.runCommandLocal "ironbar-tray-fallback-icons" { } ''
    theme_dir="$out/share/icons/${trayFallbackIconThemeName}"

    mkdir -p \
      "$theme_dir/16x16/status" \
      "$theme_dir/22x22/status" \
      "$theme_dir/24x24/status"

    cat > "$theme_dir/index.theme" <<'EOF'
    [Icon Theme]
    Name=Papirus-Dark-Fallback
    Comment=Papirus-Dark with a custom missing tray icon
    Inherits=Papirus-Dark
    Directories=16x16/status,22x22/status,24x24/status

    [16x16/status]
    Size=16
    Context=Status
    Type=Fixed

    [22x22/status]
    Size=22
    Context=Status
    Type=Fixed

    [24x24/status]
    Size=24
    Context=Status
    Type=Fixed
    EOF

    ln -s "${pkgs.papirus-icon-theme}/share/icons/Papirus/16x16/symbolic/mimetypes/application-x-executable-symbolic.svg" \
      "$theme_dir/16x16/status/image-missing.svg"
    ln -s "${pkgs.papirus-icon-theme}/share/icons/Papirus/22x22/symbolic/mimetypes/application-x-executable-symbolic.svg" \
      "$theme_dir/22x22/status/image-missing.svg"
    ln -s "${pkgs.papirus-icon-theme}/share/icons/Papirus/24x24/symbolic/mimetypes/application-x-executable-symbolic.svg" \
      "$theme_dir/24x24/status/image-missing.svg"
  '';
  ironbarXdgDataDirs = lib.concatStringsSep ":" [
    "${trayFallbackIconTheme}/share"
    "/etc/profiles/per-user/${config.home.username}/share"
    "/run/current-system/sw/share"
    "${pkgs.papirus-icon-theme}/share"
    "${pkgs.adwaita-icon-theme}/share"
    "${pkgs.hicolor-icon-theme}/share"
  ];
  scripts = import ./scripts.nix { inherit lib config pkgs; };
in
{
  options.local.niri.ironbar.enable = lib.mkEnableOption "Ironbar status bar";

  config = lib.mkIf (cfg.enable && cfg.ironbar.enable) {
    programs.ironbar = {
      enable = true;
      systemd = true;

      config = {
        ironvar_defaults = {
          nvidia_popup_text = "Click to load...";
          sunsetr_icon = ''<span color="${palette.muted}">󰖔</span>'';
          sunsetr_tooltip = "Night light: Off";
          notifications_dnd_state = "Unknown";
          notifications_tooltip = ''
            Left click: toggle notifications panel
            Right click: toggle Do Not Disturb
            DND: Unknown
          '';
          power_profile_icon = "";
          power_profile_tooltip = "Power profile: Balanced";
          power_profile_current = "Current: Balanced";
        };
        icon_theme = trayFallbackIconThemeName;
        name = "main";
        position = "top";
        anchor_to_edges = true;
        height = 44;
        autohide = 1500;
        exclusive_zone = true;
        popup_autohide = true;

        start = [
          {
            type = "clock";
            format = "%a %b %d  %H:%M";
          }
        ];

        center = [
          {
            type = "workspaces";
            all_monitors = false;
          }
        ];

        end =
          lib.optional (cfg.dgpuPciPath != null) {
            type = "custom";
            name = "nvidia-status";
            class = "nvidia-status";
            bar = [
              {
                type = "button";
                name = "nvidia-status-button";
                class = "nvidia-status-button";
                label = "{{30000:${scripts.nvidiaStatusIcon}}}";
                on_click = "!${scripts.nvidiaStatusPopupClick}";
              }
            ];
            popup = [
              {
                type = "box";
                name = "nvidia-popup";
                orientation = "vertical";
                widgets = [
                  {
                    type = "label";
                    name = "nvidia-popup-title";
                    label = "<span weight='bold'>NVIDIA dGPU</span>";
                  }
                  {
                    type = "label";
                    name = "nvidia-popup-details";
                    label = "#nvidia_popup_text";
                    justify = "left";
                  }
                ];
              }
            ];
          }
          ++ [
            {
              type = "custom";
              name = "power-profile-selector";
              class = "power-profile";
              tooltip = "#power_profile_tooltip";
              bar = [
                {
                  type = "button";
                  name = "power-profile-button";
                  label = "#power_profile_icon";
                  on_click = "popup:toggle";
                }
              ];
              popup = [
                {
                  type = "box";
                  name = "power-profile-popup";
                  orientation = "vertical";
                  widgets = [
                    {
                      type = "label";
                      name = "power-profile-title";
                      label = "<span weight='bold'>Power profile</span>";
                    }
                    {
                      type = "label";
                      name = "power-profile-current";
                      label = "#power_profile_current";
                    }
                    {
                      type = "button";
                      class = "power-profile-option";
                      label = "Power Saver";
                      on_click = "!${scripts.powerProfileSet} power-saver";
                    }
                    {
                      type = "button";
                      class = "power-profile-option";
                      label = "Balanced";
                      on_click = "!${scripts.powerProfileSet} balanced";
                    }
                    {
                      type = "button";
                      class = "power-profile-option";
                      label = "Performance";
                      on_click = "!${scripts.powerProfileSet} performance";
                    }
                  ];
                }
              ];
            }
            {
              type = "network_manager";
              icon_size = 18;
              class = "wifi";
              types_whitelist = [ "wifi" ];
              on_click_left = "${scripts.openNetworkSettings}";
              profiles.wifi_disconnected = {
                when = {
                  type = "wifi";
                  state = "disconnected";
                };
                icon = "icon:network-wireless-disabled-symbolic";
              };
            }
            {
              type = "bluetooth";
              format = {
                not_found = "";
                disabled = "";
                enabled = "";
                connected = "";
                connected_battery = "";
              };
              popup.header = " Bluetooth";
              popup.max_height.devices = 6;
            }
            {
              type = "volume";
              format = "{icon}";
              max_volume = 150;
              icons = {
                volume_high = "󰕾";
                volume_medium = "󰖀";
                volume_low = "󰕿";
                muted = "󰝟";
              };
            }
            {
              type = "custom";
              class = "sunsetr-toggle";
              name = "sunsetr-toggle";
              bar = [
                {
                  type = "button";
                  name = "sunsetr-toggle-button";
                  label = "#sunsetr_icon";
                  on_click = "!${scripts.sunsetrToggle}";
                }
              ];
              tooltip = "#sunsetr_tooltip";
            }
            {
              type = "battery";
              format = " {percentage}%";
              show_icon = false;
              disable_popup = true;
              profiles = {
                charging = {
                  when = {
                    percent = 100;
                    charging = true;
                  };
                  format = " {percentage}%";
                };
                good = {
                  when = {
                    percent = 89;
                    charging = false;
                  };
                  format = " {percentage}%";
                };
                medium = {
                  when = {
                    percent = 59;
                    charging = false;
                  };
                  format = " {percentage}%";
                };
                warning = {
                  when = {
                    percent = 39;
                    charging = false;
                  };
                  format = " {percentage}%";
                };
                critical = {
                  when = {
                    percent = 14;
                    charging = false;
                  };
                  format = " {percentage}%";
                };
              };
            }
            {
              type = "notifications";
              show_count = true;
              tooltip = "#notifications_tooltip";
              on_click_left = "${scripts.notificationsDismissAll}";
              on_click_right = "${scripts.notificationsToggleDnd}";
            }
            {
              type = "tray";
              prefer_theme_icons = false;
            }
          ];
      };

      style = ''
        @define-color bg alpha(${palette.background}, 0.7);
        @define-color fg ${palette.foreground};
        @define-color accent ${palette.accent};

        * {
          font-family: "${fontFamily}", monospace;
          font-size: 14px;
          color: @fg;
        }

        .background {
          background: transparent;
        }

        #bar #start,
        #bar #center,
        #bar #end {
          background: @bg;
          border-radius: 10px;
          margin: 4px;
          padding: 0 4px;
        }

        .workspaces .item {
          padding: 0 8px;
          color: ${palette.muted};
          border-radius: 8px;
          margin: 2px;
          transition: all 200ms cubic-bezier(0.34, 1.56, 0.64, 1);
        }

        .workspaces .item.focused {
          color: @accent;
          background: alpha(@accent, 0.2);
        }

        .workspaces .item:hover {
          background: alpha(@accent, 0.4);
          border-radius: 8px;
          margin-top: -1px;
          margin-bottom: 3px;
        }

        #bar #end > * {
          padding: 0 14px;
          margin-top: 0;
          margin-bottom: 0;
          transition: margin 200ms cubic-bezier(0.34, 1.56, 0.64, 1);
        }

        #bar #end > *:hover {
          margin-top: -3px;
          margin-bottom: 3px;
        }

        .tray .item {
          padding: 0 6px;
        }

        .battery.profile-warning .label {
          color: ${palette.warning};
        }

        .battery.profile-critical .label {
          color: ${palette.danger};
        }

        .bluetooth.disabled {
          color: ${palette.muted};
        }

        .bluetooth.connected {
          color: @accent;
        }

        ${tooltipCss}

        .power-profile #power-profile-button,
        .power-profile #power-profile-button:hover,
        .power-profile #power-profile-button:active {
          background: transparent;
          background-image: none;
          border: none;
          box-shadow: none;
          padding: 0;
        }

        .popup-power-profile {
          min-width: 190px;
          background: alpha(@bg, 0.98);
          border: 1px solid alpha(@accent, 0.28);
          border-radius: 14px;
          box-shadow: 0 14px 32px alpha(#000000, 0.4);
          padding: 10px 0 6px;
        }

        .popup-power-profile #power-profile-title {
          color: @accent;
          padding: 0 14px 4px;
        }

        .popup-power-profile #power-profile-current {
          color: ${palette.muted};
          padding: 0 14px 10px;
        }

        .popup-power-profile .power-profile-option {
          background: alpha(@accent, 0.06);
          border: 1px solid alpha(@accent, 0.12);
          border-radius: 10px;
          margin: 0 10px 6px;
          padding: 8px 12px;
        }

        .popup-power-profile .power-profile-option:hover {
          background: alpha(@accent, 0.18);
          border-color: alpha(@accent, 0.3);
        }

        .popup-power-profile .power-profile-option:active {
          background: alpha(@accent, 0.26);
        }

        .nvidia-status-button,
        .nvidia-status-button:hover,
        .nvidia-status-button:active {
          background: transparent;
          background-image: none;
          border: none;
          box-shadow: none;
          padding: 0;
        }

        .sunsetr-toggle #sunsetr-toggle-button,
        .sunsetr-toggle #sunsetr-toggle-button:hover,
        .sunsetr-toggle #sunsetr-toggle-button:active {
          background: transparent;
          background-image: none;
          border: none;
          box-shadow: none;
          padding: 0;
        }

        #nvidia-popup {
          padding: 8px 0;
        }

        #nvidia-popup-title {
          color: @accent;
          padding: 0 12px 8px;
        }

        #nvidia-popup-details {
          padding: 0 12px 8px;
        }
      '';
    };

    systemd.user.services.ironbar.Service.Environment = [
      "__EGL_VENDOR_LIBRARY_FILENAMES=/run/opengl-driver/share/glvnd/egl_vendor.d/50_mesa.json"
      "GDK_BACKEND=wayland"
      "GSK_RENDERER=cairo"
      "LIBGL_ALWAYS_SOFTWARE=1"
      "XDG_DATA_DIRS=${ironbarXdgDataDirs}"
    ];

    systemd.user.services.ironbar-power-profile = {
      Unit = {
        Description = "Update Ironbar power profile state";
        PartOf = [
          "graphical-session.target"
          "ironbar.service"
        ];
        After = [
          "graphical-session.target"
          "ironbar.service"
        ];
      };
      Service = {
        ExecStart = "${scripts.powerProfileIronbarWatch}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.ironbar-sunsetr-state = {
      Unit = {
        Description = "Update Ironbar sunsetr state";
        PartOf = [
          "graphical-session.target"
          "ironbar.service"
        ];
        After = [
          "graphical-session.target"
          "ironbar.service"
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${scripts.sunsetrIronbarUpdate}";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.timers.ironbar-sunsetr-state = {
      Unit.Description = "Refresh Ironbar sunsetr state";
      Timer = {
        OnBootSec = "10s";
        OnUnitActiveSec = "30s";
        Unit = "ironbar-sunsetr-state.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };

    systemd.user.services.ironbar-dnd-state = {
      Unit = {
        Description = "Update Ironbar notification DND state";
        PartOf = [
          "graphical-session.target"
          "ironbar.service"
        ];
        After = [
          "graphical-session.target"
          "ironbar.service"
        ];
      };
      Service = {
        Type = "oneshot";
        ExecStart = "${scripts.notificationsDndIronbarUpdate}";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.timers.ironbar-dnd-state = {
      Unit.Description = "Refresh Ironbar notification DND state";
      Timer = {
        OnBootSec = "10s";
        OnUnitActiveSec = "30s";
        Unit = "ironbar-dnd-state.service";
      };
      Install.WantedBy = [ "timers.target" ];
    };
  };
}
