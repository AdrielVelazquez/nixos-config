{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  palette = cfg.style.palette;
  ironbarBin = lib.getExe pkgs.ironbar;
  brightnessctlBin = lib.getExe pkgs.brightnessctl;
  cliphistBin = lib.getExe pkgs.cliphist;
  grimBin = lib.getExe pkgs.grim;
  hyprlockBin = if cfg.useSystemHyprlock then "/usr/bin/hyprlock" else lib.getExe pkgs.hyprlock;
  notifySendBin = lib.getExe' pkgs.libnotify "notify-send";
  playerctlBin = lib.getExe pkgs.playerctl;
  sattyBin = lib.getExe pkgs.satty;
  slurpBin = lib.getExe pkgs.slurp;
  swayncClient = lib.getExe' pkgs.swaynotificationcenter "swaync-client";
  systemctlBin = lib.getExe' pkgs.systemd "systemctl";
  powerProfilesCtl = lib.getExe' pkgs."power-profiles-daemon" "powerprofilesctl";
  walkerBin = lib.getExe pkgs.walker;
  wlCopyBin = lib.getExe' pkgs.wl-clipboard "wl-copy";
  wpctlBin = lib.getExe' pkgs.wireplumber "wpctl";
  awkBin = lib.getExe pkgs.gawk;
  dgpuPciPath = if cfg.dgpuPciPath == null then "/run/no-dgpu-configured" else cfg.dgpuPciPath;
  brightnessctlCommand =
    brightnessctlBin
    + lib.optionalString (
      cfg.brightnessDevice != null
    ) " --device ${lib.escapeShellArg cfg.brightnessDevice}";
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
in
rec {
  inherit swayncClient;

  swayncTogglePanel = mkShellApplication {
    name = "swaync-toggle-panel";
    text = ''
      ${swayncClient} --toggle-panel --skip-wait
    '';
  };

  lockScreen = mkShellApplication {
    name = "niri-lock-screen";
    text = ''
      ${hyprlockBin} --grace 2
    '';
  };

  ironbarToggleVisible = mkShellApplication {
    name = "ironbar-toggle-visible";
    text = ''
      ${ironbarBin} bar main toggle-visible
    '';
  };

  clipboardHistoryPick = mkShellApplication {
    name = "clipboard-history-pick";
    text = ''
      ${cliphistBin} list | ${walkerBin} --dmenu | ${cliphistBin} decode | ${wlCopyBin}
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

  sunsetrStatusIcon = mkShellApplication {
    name = "sunsetr-status-icon";
    text = ''
      if ${systemctlBin} --user is-active --quiet sunsetr.service; then
        printf '<span color="${palette.accent}">󰖔</span>\n'
      else
        printf '<span color="${palette.muted}">󰖔</span>\n'
      fi
    '';
  };

  sunsetrStatusPretty = mkShellApplication {
    name = "sunsetr-status-pretty";
    text = ''
      if ${systemctlBin} --user is-active --quiet sunsetr.service; then
        printf 'On\n'
      else
        printf 'Off\n'
      fi
    '';
  };

  sunsetrToggle = mkShellApplication {
    name = "sunsetr-toggle";
    text = ''
      if ${systemctlBin} --user is-active --quiet sunsetr.service; then
        ${systemctlBin} --user stop sunsetr.service
      else
        ${systemctlBin} --user start sunsetr.service
      fi
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

  nvidiaStatusPopupClick = mkShellApplication {
    name = "nvidia-status-popup-click";
    text = ''
      payload="$(${nvidiaStatusPopupRender})"

      ${ironbarBin} var set nvidia_popup_text "$payload" >/dev/null

      if ! ${ironbarBin} bar main toggle-popup nvidia-status >/dev/null 2>&1; then
        ${ironbarBin} bar main toggle-popup nvidia-status-button >/dev/null
      fi
    '';
  };

  powerProfileCurrent = mkShellApplication {
    name = "power-profile-current";
    text = ''
      current="$(${powerProfilesCtl} get 2>/dev/null || printf 'balanced')"
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

      ${ironbarBin} bar main set-popup-visible power-profile-selector false >/dev/null 2>&1 || \
        ${ironbarBin} bar main set-popup-visible power-profile-button false >/dev/null 2>&1 || true
    '';
  };
}
