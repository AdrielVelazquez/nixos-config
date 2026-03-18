# modules/home-manager/niri/ironbar.nix
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
  ironbarXdgDataDirs = lib.concatStringsSep ":" [
    "/etc/profiles/per-user/${config.home.username}/share"
    "/run/current-system/sw/share"
    "${pkgs.papirus-icon-theme}/share"
    "${pkgs.adwaita-icon-theme}/share"
    "${pkgs.hicolor-icon-theme}/share"
  ];
  nvidiaPciPath = "/sys/bus/pci/devices/0000:c4:00.0";
  ironbarBin = lib.getExe pkgs.ironbar;
  nvidiaStatusIcon = pkgs.writeShellScript "nvidia-status-icon" ''
    state=$(cat "${nvidiaPciPath}/power_state" 2>/dev/null || printf 'unknown')
    case "$state" in
      D3cold) echo '<span color="${palette.muted}">󰍹</span>' ;;
      D3hot)  echo '<span color="${palette.warning}">󰍹</span>' ;;
      *)      echo '<span color="${palette.danger}">󰍹</span>' ;;
    esac
  '';
  nvidiaStatusPopupRender = pkgs.writeShellScript "nvidia-status-popup-render" ''
    power_state=$(cat "${nvidiaPciPath}/power_state" 2>/dev/null || printf 'unknown')
    runtime_status=$(cat "${nvidiaPciPath}/power/runtime_status" 2>/dev/null || printf 'unknown')
    sed_bin=${pkgs.gnused}/bin/sed
    grep_bin=${pkgs.gnugrep}/bin/grep
    sort_bin=${pkgs.coreutils}/bin/sort
    tr_bin=${pkgs.coreutils}/bin/tr
    awk_bin=${pkgs.gawk}/bin/awk

    is_generic_name() {
      case "''${1,,}" in
        ""|bash|sh|env|systemd|wine|wine64|wine-preloader|wine64-preloader|wineserver|gamethread|renderthread)
          return 0
          ;;
        *)
          return 1
          ;;
      esac
    }

    pretty_name() {
      local name=$1
      name=$(printf '%s\n' "$name" | "$sed_bin" -E 's#.*[\\/]##')
      name=''${name#.}
      name=''${name%-wrapped}
      name=''${name%.exe}
      name=''${name%.EXE}

      case "''${name,,}" in
        swaync) printf 'SwayNC' ;;
        ironbar) printf 'Ironbar' ;;
        walker) printf 'Walker' ;;
        steam) printf 'Steam' ;;
        steamwebhelper) printf 'Steam WebHelper' ;;
        *) printf '%s' "$name" ;;
      esac
    }

    resolve_process_name() {
      local pid=$1
      local comm exe exe_base first_base last_exe=""
      local arg base
      local -a args=()

      if [ -r "/proc/$pid/cmdline" ]; then
        mapfile -d "" -t args < "/proc/$pid/cmdline" || true
      fi

      comm=$(cat "/proc/$pid/comm" 2>/dev/null || true)
      exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)

      for arg in "''${args[@]}"; do
        base=''${arg##*/}
        case "$base" in
          *.exe|*.EXE)
            last_exe=$base
            ;;
        esac
      done

      if is_generic_name "$comm" && [ -n "$last_exe" ]; then
        pretty_name "$last_exe"
        return 0
      fi

      if [ "''${#args[@]}" -gt 0 ]; then
        first_base=''${args[0]##*/}
        if ! is_generic_name "$first_base"; then
          pretty_name "$first_base"
          return 0
        fi
      fi

      exe_base=''${exe##*/}
      if ! is_generic_name "$exe_base"; then
        pretty_name "$exe_base"
        return 0
      fi

      if [ -n "$last_exe" ]; then
        pretty_name "$last_exe"
        return 0
      fi

      if [ -n "$comm" ]; then
        pretty_name "$comm"
        return 0
      fi

      printf 'PID %s' "$pid"
    }

    env_has_key() {
      local pid=$1
      local pattern=$2
      [ -r "/proc/$pid/environ" ] || return 1
      "$tr_bin" '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | "$grep_bin" -Eq "$pattern"
    }

    cmdline_has_windows_path() {
      local pid=$1
      [ -r "/proc/$pid/cmdline" ] || return 1
      "$tr_bin" '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | "$grep_bin" -Eq '^[A-Za-z]:\\|\\'
    }

    process_icon() {
      local pid=$1
      local name=$2

      if env_has_key "$pid" '^STEAM_COMPAT_APP_ID='; then
          printf ''
          return 0
      fi

      if env_has_key "$pid" '^(WINEPREFIX|WINELOADER|WINESERVER)=' || cmdline_has_windows_path "$pid"; then
        printf ''
        return 0
      fi

      case "''${name,,}" in
        *steam*)
          printf ''
          return 0
          ;;
      esac

      if env_has_key "$pid" '^(SteamGameId|SteamAppId)='; then
        printf ''
        return 0
      fi

      printf ''
    }

    printf 'Power state: %s\n' "$power_state"
    printf 'Runtime PM:  %s\n' "$runtime_status"

    if [ "$runtime_status" = "suspended" ]; then
      printf '\nGPU is asleep.\n'
      exit 0
    fi

    declare -A entry_counts=()
    declare -A entry_pids=()

    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      [ -d "/proc/$pid" ] || continue

      name=$(resolve_process_name "$pid")
      icon=$(process_icon "$pid" "$name")
      entry="$icon $name"
      entry_counts["$entry"]=$(( ''${entry_counts["$entry"]:-0} + 1 ))

      if [ -n "''${entry_pids["$entry"]:-}" ]; then
        entry_pids["$entry"]="''${entry_pids["$entry"]}, $pid"
      else
        entry_pids["$entry"]="$pid"
      fi
    done < <(
      ${pkgs.psmisc}/bin/fuser /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm 2>/dev/null \
        | "$awk_bin" '{for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) print $i}' \
        | "$sort_bin" -nu
    )

    if [ "''${#entry_counts[@]}" -eq 0 ]; then
      printf '\nGPU is awake, but no user-visible /dev/nvidia* handles were found.\n'
      exit 0
    fi

    printf '\nProcesses:\n'
    while IFS= read -r entry; do
      [ -n "$entry" ] || continue

      if [ "''${entry_counts["$entry"]}" -gt 1 ]; then
        printf '%s x%s (%s)\n' "$entry" "''${entry_counts["$entry"]}" "''${entry_pids["$entry"]}"
      else
        printf '%s (%s)\n' "$entry" "''${entry_pids["$entry"]}"
      fi
    done < <(printf '%s\n' "''${!entry_counts[@]}" | "$sort_bin" -f -k2)
  '';
  nvidiaStatusPopupClick = pkgs.writeShellScript "nvidia-status-popup-click" ''
    payload="$(${nvidiaStatusPopupRender})"

    ${ironbarBin} var set nvidia_popup_text "$payload" >/dev/null

    if ! ${ironbarBin} bar main show-popup nvidia-status >/dev/null 2>&1; then
      ${ironbarBin} bar main show-popup nvidia-status-button >/dev/null
    fi
  '';
in
{
  options.local.niri.ironbar.enable = lib.mkEnableOption "Ironbar status bar";

  config = lib.mkIf (cfg.enable && cfg.ironbar.enable) {
    programs.ironbar = {
      enable = true;
      systemd = true;

      config = {
        ironvar_defaults.nvidia_popup_text = "Click to load...";
        icon_theme = "Papirus-Dark";
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
          lib.optional cfg.hasDgpu {
            type = "custom";
            name = "nvidia-status";
            class = "nvidia-status";
            bar = [
              {
                type = "button";
                name = "nvidia-status-button";
                class = "nvidia-status-button";
                label = "{{2000:${nvidiaStatusIcon}}}";
                on_click = "!${nvidiaStatusPopupClick}";
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
              type = "script";
              cmd = "${pkgs.writeShellScript "power-profile-watch" ''
                show() {
                  case "$(powerprofilesctl get 2>/dev/null)" in
                  performance) printf '\u26a1\n' ;;
                  balanced)    printf '\U000f24e\n' ;;
                  power-saver) printf '\U000f06c\n' ;;
                  *)           printf '\U000f24e\n' ;;
                esac
                }
                trap show USR1
                while true; do
                  show
                  sleep 60 &
                  wait $!
                done
              ''}";
              mode = "watch";
              class = "power-profile";
              on_click_left = "${pkgs.writeShellScript "cycle-power-profile" ''
                current=$(powerprofilesctl get 2>/dev/null)
                case "$current" in
                  balanced)    powerprofilesctl set performance ;;
                  performance) powerprofilesctl set power-saver ;;
                  *)           powerprofilesctl set balanced ;;
                esac
                pkill -USR1 -f power-profile-watch
              ''}";
            }
            {
              type = "network_manager";
              icon_size = 18;
              class = "wifi";
              types_whitelist = [ "wifi" ];
              on_click_left = "kitty @ --to unix:$(ls /tmp/kitty-* 2>/dev/null | head -n1) launch --type=tab --tab-title Network nmtui || kitty nmtui";
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
              max_volume = 100;
              icons = {
                volume_high = "󰕾";
                volume_medium = "󰖀";
                volume_low = "󰕿";
                muted = "󰝟";
              };
              on_click_left = "pwvucontrol";
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
              type = "tray";
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

        .nvidia-status-button,
        .nvidia-status-button:hover,
        .nvidia-status-button:active {
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
      "XDG_DATA_DIRS=${ironbarXdgDataDirs}"
    ];
  };
}
