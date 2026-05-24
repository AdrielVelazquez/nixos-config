{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  brightnessctlBin = lib.getExe pkgs.brightnessctl;
  cliphistBin = lib.getExe pkgs.cliphist;
  grimBin = lib.getExe pkgs.grim;
  hyprlockBin = if cfg.useSystemHyprlock then "/usr/bin/hyprlock" else lib.getExe pkgs.hyprlock;
  notifySendBin = lib.getExe' pkgs.libnotify "notify-send";
  playerctlBin = lib.getExe pkgs.playerctl;
  sattyBin = lib.getExe pkgs.satty;
  slurpBin = lib.getExe pkgs.slurp;
  wlScreenrecBin = lib.getExe pkgs.wl-screenrec;
  makoCtlBin = lib.getExe' pkgs.mako "makoctl";
  busctlBin = lib.getExe' pkgs.systemd "busctl";
  systemctlBin = lib.getExe' pkgs.systemd "systemctl";
  systemdRunBin = lib.getExe' pkgs.systemd "systemd-run";
  powerProfilesCtl = lib.getExe' pkgs."power-profiles-daemon" "powerprofilesctl";
  fuzzelBin = lib.getExe pkgs.fuzzel;
  grepBin = lib.getExe pkgs.gnugrep;
  jqBin = lib.getExe pkgs.jq;
  timeoutBin = lib.getExe' pkgs.coreutils "timeout";
  basenameBin = lib.getExe' pkgs.coreutils "basename";
  catBin = lib.getExe' pkgs.coreutils "cat";
  dateBin = lib.getExe' pkgs.coreutils "date";
  mkdirBin = lib.getExe' pkgs.coreutils "mkdir";
  rmBin = lib.getExe' pkgs.coreutils "rm";
  wlCopyBin = lib.getExe' pkgs.wl-clipboard "wl-copy";
  wpctlBin = lib.getExe' pkgs.wireplumber "wpctl";
  awkBin = lib.getExe pkgs.gawk;
  bluetuiBin = lib.getExe pkgs.bluetui;
  wiremixBin = lib.getExe pkgs.wiremix;
  dgpuPciPath = if cfg.dgpuPciPath == null then "/run/no-dgpu-configured" else cfg.dgpuPciPath;
  brightnessctlCommand =
    brightnessctlBin
    + lib.optionalString (
      cfg.brightnessDevice != null
    ) " --device ${lib.escapeShellArg cfg.brightnessDevice}";
  clipboardMenu = "${fuzzelBin} --dmenu --prompt ${lib.escapeShellArg "Clipboard: "}";
  mkShellApplication =
    {
      name,
      runtimeInputs ? [ ],
      text,
    }:
    lib.getExe (
      pkgs.writeShellApplication {
        inherit name runtimeInputs text;
      }
    );
  waybarSignal =
    signal:
    "${systemctlBin} --user kill --kill-whom=main --signal=SIGRTMIN+${builtins.toString signal} waybar.service >/dev/null 2>&1 || true";
in
rec {
  notificationsDismissAll = mkShellApplication {
    name = "notifications-dismiss-all";
    text = ''
      ${timeoutBin} 1 ${makoCtlBin} dismiss --all >/dev/null 2>&1 || true
      ${waybarSignal 3}
    '';
  };

  notificationsRestore = mkShellApplication {
    name = "notifications-restore";
    text = ''
      ${timeoutBin} 1 ${makoCtlBin} restore >/dev/null 2>&1 || true
      ${waybarSignal 3}
    '';
  };

  notificationsHistoryPicker = mkShellApplication {
    name = "notifications-history-picker";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      history="$(${timeoutBin} 1 ${makoCtlBin} history -j 2>/dev/null || true)"
      entries="$(
        printf '%s\n' "$history" | ${jqBin} -r '
          def field($names):
            reduce $names[] as $name (null; . // .[$name]?);

          def line:
            (field(["app-name", "app_name", "app", "application"]) // "notification" | tostring) as $app
            | (field(["summary", "title"]) // "" | tostring) as $summary
            | (field(["body", "message"]) // "" | tostring | gsub("\\s+"; " ") | .[0:180]) as $body
            | if $body == "" then
                "\($app) | \($summary)"
              else
                "\($app) | \($summary) - \($body)"
              end;

          [
            .. | objects | select(has("summary") or has("title") or has("body") or has("message"))
          ]
          | unique_by([(.id // ""), (.summary // .title // ""), (.body // .message // "")])
          | reverse
          | .[]
          | line
        ' 2>/dev/null || true
      )"

      if [ -z "$entries" ]; then
        entries="No notification history"
      fi

      selected="$(printf '%s\n' "$entries" | ${fuzzelBin} --dmenu --prompt "Notifications: " || true)"
      if [ -n "$selected" ] && [ "$selected" != "No notification history" ]; then
        printf '%s\n' "$selected" | ${wlCopyBin}
      fi
    '';
  };

  notificationsDndState = mkShellApplication {
    name = "notifications-dnd-state";
    text = ''
      state="Off"
      if modes="$(${timeoutBin} 1 ${makoCtlBin} mode 2>/dev/null)"; then
        if printf '%s\n' "$modes" | ${grepBin} -qw 'do-not-disturb'; then
          state="On"
        fi
      else
        state="Unknown"
      fi

      printf '%s\n' "$state"
    '';
  };

  notificationsWaybarStatus = mkShellApplication {
    name = "notifications-waybar-status";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      count="$(${timeoutBin} 1 ${makoCtlBin} list -j 2>/dev/null | ${jqBin} 'if type == "array" then length elif type == "object" and has("data") and (.data | type == "array") then .data | length else 0 end' 2>/dev/null || printf '0')"
      case "$count" in
        ""|*[!0-9]*) count=0 ;;
      esac

      dnd="$(${notificationsDndState})"
      case "$dnd" in
        On)
          dnd='On'
          class='dnd'
          text="󰂛 $count"
          ;;
        Off)
          dnd='Off'
          if [ "$count" -gt 0 ]; then
            class='unread'
            text="󰂚 $count"
          else
            class='clear'
            text='󰂚'
          fi
          ;;
        *)
          dnd='Unknown'
          class='unknown'
          text='󰂚'
          ;;
      esac

      tooltip="$(
        printf 'Left click: dismiss notifications\n'
        printf 'Middle click: restore last notification\n'
        printf 'Right click: toggle Do Not Disturb\n'
        printf 'DND: %s\n' "$dnd"
        printf 'Visible notifications: %s\n' "$count"
      )"

      ${jqBin} -nc \
        --arg text "$text" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    '';
  };

  notificationsToggleDnd = mkShellApplication {
    name = "notifications-toggle-dnd";
    text = ''
      ${timeoutBin} 1 ${makoCtlBin} mode -t do-not-disturb >/dev/null 2>&1 || true
      ${waybarSignal 3}
    '';
  };

  lockScreen = mkShellApplication {
    name = "niri-lock-screen";
    text = ''
      ${hyprlockBin} --grace 2
    '';
  };

  barToggleVisible = mkShellApplication {
    name = "niri-bar-toggle-visible";
    text = ''
      if ${systemctlBin} --user is-active --quiet waybar.service 2>/dev/null; then
        ${systemctlBin} --user kill --kill-whom=main --signal=SIGUSR1 waybar.service
      fi
    '';
  };

  clipboardHistoryPick = mkShellApplication {
    name = "clipboard-history-pick";
    text = ''
      ${cliphistBin} list | ${clipboardMenu} | ${cliphistBin} decode | ${wlCopyBin}
    '';
  };

  screenshotAnnotate = mkShellApplication {
    name = "screenshot-annotate";
    text = ''
      screenshot_dir="$HOME/Pictures/Screenshots"
      ${pkgs.coreutils}/bin/mkdir -p "$screenshot_dir"

      output="$screenshot_dir/Screenshot from $(${pkgs.coreutils}/bin/date +'%Y-%m-%d %H-%M-%S').png"
      ${grimBin} -g "$(${slurpBin})" - | ${sattyBin} -f - --output-filename "$output" --copy-command ${wlCopyBin}
    '';
  };

  screenRecordToggle = mkShellApplication {
    name = "screen-record-toggle";
    text = ''
      unit_name="wl-screenrec-session"
      unit="$unit_name.service"
      state_dir="''${XDG_RUNTIME_DIR:-/tmp}/screen-record-toggle"
      output_state="$state_dir/output"
      recording_dir="$HOME/Videos/Screencasts"

      ${mkdirBin} -p "$recording_dir" "$state_dir"

      if ${systemctlBin} --user is-active --quiet "$unit"; then
        output="$(${catBin} "$output_state" 2>/dev/null || true)"
        ${systemctlBin} --user stop "$unit"
        ${rmBin} -f "$output_state"

        if [ -n "$output" ]; then
          ${notifySendBin} -a "Screen Recording" -t 3000 "Recording stopped" "$(${basenameBin} "$output")"
        else
          ${notifySendBin} -a "Screen Recording" -t 3000 "Recording stopped"
        fi
        exit 0
      fi

      geometry="$(${slurpBin} || true)"
      if [ -z "$geometry" ]; then
        ${notifySendBin} -a "Screen Recording" -t 1500 "Recording cancelled"
        exit 0
      fi

      output="$recording_dir/Screen recording from $(${dateBin} +'%Y-%m-%d %H-%M-%S').mp4"
      printf '%s\n' "$output" > "$output_state"

      if ${systemdRunBin} --user --quiet --collect --unit "$unit_name" \
        --property "Description=wl-screenrec screen recording" \
        --property "KillSignal=SIGINT" \
        --property "TimeoutStopSec=10" \
        ${wlScreenrecBin} -g "$geometry" -f "$output"; then
        ${notifySendBin} -a "Screen Recording" -t 3000 "Recording started" "$(${basenameBin} "$output")"
      else
        ${rmBin} -f "$output_state"
        ${notifySendBin} -a "Screen Recording" -u critical -t 5000 "Failed to start recording"
        exit 1
      fi
    '';
  };

  volumeRaise = mkShellApplication {
    name = "volume-raise";
    text = ''
      ${wpctlBin} set-volume @DEFAULT_AUDIO_SINK@ 5%+ -l 1.5
      vol=$(${wpctlBin} get-volume @DEFAULT_AUDIO_SINK@ | ${awkBin} '{printf "%.0f", $2*100}')
      ${notifySendBin} -t 1500 -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume '󰕾 Volume' "$vol%"
    '';
  };

  volumeLower = mkShellApplication {
    name = "volume-lower";
    text = ''
      ${wpctlBin} set-volume @DEFAULT_AUDIO_SINK@ 5%- -l 1.5
      vol=$(${wpctlBin} get-volume @DEFAULT_AUDIO_SINK@ | ${awkBin} '{printf "%.0f", $2*100}')
      ${notifySendBin} -t 1500 -h int:value:"$vol" -h string:x-canonical-private-synchronous:volume '󰕾 Volume' "$vol%"
    '';
  };

  volumeMute = mkShellApplication {
    name = "volume-mute";
    text = ''
      ${wpctlBin} set-mute @DEFAULT_AUDIO_SINK@ toggle
      ${notifySendBin} -t 1500 -h string:x-canonical-private-synchronous:volume '󰝟 Mute toggled'
    '';
  };

  micMute = mkShellApplication {
    name = "mic-mute";
    text = ''
      ${wpctlBin} set-mute @DEFAULT_AUDIO_SOURCE@ toggle
      ${notifySendBin} -t 1500 -h string:x-canonical-private-synchronous:mic '🎤 Mic mute toggled'
    '';
  };

  mediaPlayPause = mkShellApplication {
    name = "media-play-pause";
    text = ''
      ${playerctlBin} play-pause
    '';
  };

  mediaStop = mkShellApplication {
    name = "media-stop";
    text = ''
      ${playerctlBin} stop
    '';
  };

  mediaPrevious = mkShellApplication {
    name = "media-previous";
    text = ''
      ${playerctlBin} previous
    '';
  };

  mediaNext = mkShellApplication {
    name = "media-next";
    text = ''
      ${playerctlBin} next
    '';
  };

  brightnessRaise = mkShellApplication {
    name = "brightness-raise";
    text = ''
      ${brightnessctlCommand} set 5%+
      bri=$(${brightnessctlCommand} -m | ${awkBin} -F, '{gsub("%", "", $4); print $4}')
      ${notifySendBin} -t 1500 -h int:value:"$bri" -h string:x-canonical-private-synchronous:brightness '󰃠 Brightness' "$bri%"
    '';
  };

  brightnessLower = mkShellApplication {
    name = "brightness-lower";
    text = ''
      ${brightnessctlCommand} set 5%-
      bri=$(${brightnessctlCommand} -m | ${awkBin} -F, '{gsub("%", "", $4); print $4}')
      ${notifySendBin} -t 1500 -h int:value:"$bri" -h string:x-canonical-private-synchronous:brightness '󰃠 Brightness' "$bri%"
    '';
  };

  openNetworkSettings = mkShellApplication {
    name = "open-network-settings";
    runtimeInputs = [
      pkgs.kitty
      pkgs.networkmanager
    ];
    text = ''
      socket=""

      for candidate in /tmp/kitty-*; do
        [ -S "$candidate" ] || continue
        socket="$candidate"
        break
      done

      if [ -n "$socket" ] && kitty @ --to "unix:$socket" launch --type=tab --tab-title Network nmtui; then
        exit 0
      fi

      exec kitty nmtui
    '';
  };

  openBluetoothSettings = mkShellApplication {
    name = "open-bluetooth-settings";
    runtimeInputs = [
      pkgs.bluetui
      pkgs.kitty
    ];
    text = ''
      socket=""

      for candidate in /tmp/kitty-*; do
        [ -S "$candidate" ] || continue
        socket="$candidate"
        break
      done

      if [ -n "$socket" ] && kitty @ --to "unix:$socket" launch --type=tab --tab-title Bluetooth ${bluetuiBin}; then
        exit 0
      fi

      exec kitty ${bluetuiBin}
    '';
  };

  openAudioSettings = mkShellApplication {
    name = "open-audio-settings";
    runtimeInputs = [
      pkgs.kitty
      pkgs.wiremix
    ];
    text = ''
      socket=""

      for candidate in /tmp/kitty-*; do
        [ -S "$candidate" ] || continue
        socket="$candidate"
        break
      done

      if [ -n "$socket" ] && kitty @ --to "unix:$socket" launch --type=tab --tab-title Audio ${wiremixBin}; then
        exit 0
      fi

      exec kitty ${wiremixBin}
    '';
  };

  sunsetrToggle = mkShellApplication {
    name = "sunsetr-toggle";
    text = ''
      if ${systemctlBin} --user is-active --quiet sunsetr.service 2>/dev/null; then
        ${systemctlBin} --user stop sunsetr.service
      else
        ${systemctlBin} --user start sunsetr.service
      fi
      ${waybarSignal 2}
    '';
  };

  nvidiaStatusIcon = mkShellApplication {
    name = "nvidia-status-icon";
    text = ''
      state=$(cat "${dgpuPciPath}/power_state" 2>/dev/null || printf 'unknown')
      case "$state" in
        D3cold) printf '<span color="${palette.muted}">󰍹</span>\n' ;;
        D3hot)  printf '<span color="${palette.warning}">󰍹</span>\n' ;;
        *)      printf '<span color="${palette.danger}">󰍹</span>\n' ;;
      esac
    '';
  };

  nvidiaStatusPopupRender = mkShellApplication {
    name = "nvidia-status-popup-render";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gawk
      pkgs.gnugrep
      pkgs.gnused
      pkgs.psmisc
    ];
    text = ''
      power_state=$(cat "${dgpuPciPath}/power_state" 2>/dev/null || printf 'unknown')
      runtime_status=$(cat "${dgpuPciPath}/power/runtime_status" 2>/dev/null || printf 'unknown')

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
        name=$(printf '%s\n' "$name" | sed -E 's#.*[\\/]##')
        name=''${name#.}
        name=''${name%-wrapped}
        name=''${name%.exe}
        name=''${name%.EXE}

        case "''${name,,}" in
          fuzzel) printf 'Fuzzel' ;;
          mako) printf 'Mako' ;;
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
        tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null | grep -Eq "$pattern"
      }

      cmdline_has_windows_path() {
        local pid=$1
        [ -r "/proc/$pid/cmdline" ] || return 1
        tr '\0' '\n' < "/proc/$pid/cmdline" 2>/dev/null | grep -Eq "^[A-Za-z]:\\\\|\\\\"
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

        printf ''
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
        fuser /dev/nvidia0 /dev/nvidiactl /dev/nvidia-modeset /dev/nvidia-uvm 2>/dev/null \
          | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^[0-9]+$/) print $i}' \
          | sort -nu
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
      done < <(printf '%s\n' "''${!entry_counts[@]}" | sort -f -k2)
    '';
  };

  nvidiaWaybarStatus = mkShellApplication {
    name = "nvidia-waybar-status";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      power_state=$(cat "${dgpuPciPath}/power_state" 2>/dev/null || printf 'unknown')
      runtime_status=$(cat "${dgpuPciPath}/power/runtime_status" 2>/dev/null || printf 'unknown')

      case "$power_state" in
        D3cold)
          class='off'
          tooltip='NVIDIA dGPU: Suspended (D3cold)'
          ;;
        D3hot)
          class='idle'
          tooltip='NVIDIA dGPU: Idle (D3hot)'
          ;;
        *)
          class='active'
          tooltip="$(${nvidiaStatusPopupRender})"
          ;;
      esac

      if [ "$runtime_status" = "suspended" ] && [ "$power_state" != "D3cold" ]; then
        class='off'
      fi

      ${jqBin} -nc \
        --arg text '󰍹' \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    '';
  };

  nvidiaWaybarDetails = mkShellApplication {
    name = "nvidia-waybar-details";
    text = ''
      payload="$(${nvidiaStatusPopupRender})"
      ${notifySendBin} -t 8000 'NVIDIA dGPU' "$payload"
    '';
  };

  sunsetrWaybarStatus = mkShellApplication {
    name = "sunsetr-waybar-status";
    runtimeInputs = [ pkgs.jq ];
    text = ''
      if ${systemctlBin} --user is-active --quiet sunsetr.service 2>/dev/null; then
        class='on'
        tooltip='Night light: On (static 3300K @ 90% gamma)'
      else
        class='off'
        tooltip='Night light: Off'
      fi

      ${jqBin} -nc \
        --arg text '󰖔' \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    '';
  };

  batteryWaybarStatus = mkShellApplication {
    name = "battery-waybar-status";
    runtimeInputs = [
      pkgs.jq
      pkgs.gawk
    ];
    text = ''
      battery_dir=""
      for candidate in /sys/class/power_supply/BAT*; do
        if [ -d "$candidate" ]; then
          battery_dir="$candidate"
          break
        fi
      done

      if [ -z "$battery_dir" ]; then
        ${jqBin} -nc \
          --arg text "" \
          --arg tooltip "No battery found" \
          --arg class "missing" \
          '{text: $text, tooltip: $tooltip, class: $class}'
        exit 0
      fi

      capacity="$(cat "$battery_dir/capacity" 2>/dev/null || printf '0')"
      case "$capacity" in
        ""|*[!0-9]*) capacity=0 ;;
      esac

      status="$(cat "$battery_dir/status" 2>/dev/null || printf 'Unknown')"

      battery_icon() {
        if [ "$capacity" -le 14 ]; then
          printf ''
        elif [ "$capacity" -le 39 ]; then
          printf ''
        elif [ "$capacity" -le 59 ]; then
          printf ''
        elif [ "$capacity" -le 79 ]; then
          printf ''
        else
          printf ''
        fi
      }

      case "$status" in
        Charging)
          class="charging"
          icon=""
          ;;
        Full)
          class="full"
          icon=""
          ;;
        "Not charging")
          class="plugged"
          icon=""
          ;;
        *)
          icon="$(battery_icon)"
          if [ "$capacity" -le 14 ]; then
            class="critical"
          elif [ "$capacity" -le 39 ]; then
            class="warning"
          elif [ "$status" = "Unknown" ]; then
            class="unknown"
          else
            class="normal"
          fi
          ;;
      esac

      estimate=""
      energy_now_file=""
      energy_full_file=""
      power_now_file=""

      if [ -r "$battery_dir/energy_now" ] && [ -r "$battery_dir/energy_full" ]; then
        energy_now_file="$battery_dir/energy_now"
        energy_full_file="$battery_dir/energy_full"
      elif [ -r "$battery_dir/charge_now" ] && [ -r "$battery_dir/charge_full" ]; then
        energy_now_file="$battery_dir/charge_now"
        energy_full_file="$battery_dir/charge_full"
      fi

      if [ -r "$battery_dir/power_now" ]; then
        power_now_file="$battery_dir/power_now"
      elif [ -r "$battery_dir/current_now" ]; then
        power_now_file="$battery_dir/current_now"
      fi

      if [ -n "$energy_now_file" ] && [ -n "$power_now_file" ]; then
        energy_now="$(cat "$energy_now_file" 2>/dev/null || printf '0')"
        energy_full="$(cat "$energy_full_file" 2>/dev/null || printf '0')"
        power_now="$(cat "$power_now_file" 2>/dev/null || printf '0')"

        estimate="$(${awkBin} -v status="$status" -v now="$energy_now" -v full="$energy_full" -v power="$power_now" '
          function fmt(hours, total_minutes) {
            total_minutes = int((hours * 60) + 0.5)
            return int(total_minutes / 60) "h " total_minutes % 60 "m"
          }
          power > 0 && status == "Discharging" {
            print "Estimated remaining: " fmt(now / power)
          }
          power > 0 && status == "Charging" && full > now {
            print "Estimated full: " fmt((full - now) / power)
          }
        ')"
      fi

      tooltip="$(
        printf 'Battery: %s%%\n' "$capacity"
        printf 'Status: %s\n' "$status"
        if [ -n "$estimate" ]; then
          printf '%s\n' "$estimate"
        fi
      )"

      ${jqBin} -nc \
        --arg text "$icon $capacity%" \
        --arg tooltip "$tooltip" \
        --arg class "$class" \
        '{text: $text, tooltip: $tooltip, class: $class}'
    '';
  };

  powerProfileCurrent = mkShellApplication {
    name = "power-profile-current";
    text = ''
      current="$(
        ${busctlBin} get-property \
          net.hadess.PowerProfiles \
          /net/hadess/PowerProfiles \
          net.hadess.PowerProfiles \
          ActiveProfile 2>/dev/null | ${awkBin} -F '"' '{ print $2 }' || true
      )"
      case "$current" in
        performance|balanced|power-saver) printf '%s\n' "$current" ;;
        *) printf 'balanced\n' ;;
      esac
    '';
  };

  powerProfilePretty = mkShellApplication {
    name = "power-profile-pretty";
    text = ''
      case "$(${powerProfileCurrent})" in
        performance) printf 'Performance\n' ;;
        balanced) printf 'Balanced\n' ;;
        power-saver) printf 'Power Saver\n' ;;
      esac
    '';
  };

  powerProfileIcon = mkShellApplication {
    name = "power-profile-icon";
    text = ''
      case "$(${powerProfileCurrent})" in
        performance) printf '\u26a1\n' ;;
        balanced) printf '\U000f24e\n' ;;
        power-saver) printf '\U000f06c\n' ;;
      esac
    '';
  };

  powerProfileSet = mkShellApplication {
    name = "power-profile-set";
    text = ''
      profile="''${1:-balanced}"
      case "$profile" in
        performance|balanced|power-saver) ;;
        *) profile=balanced ;;
      esac

      ${powerProfilesCtl} set "$profile"
    '';
  };
}
