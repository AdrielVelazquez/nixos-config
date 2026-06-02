# modules/home-manager/niri/services.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.niri;
  internalDisplayCfg = cfg.services.internalDisplayAutoOff;
  jqBin = lib.getExe pkgs.jq;
  niriBin = lib.getExe config.programs.niri.package;
  sleepBin = "${pkgs.coreutils}/bin/sleep";
  sunsetrConfig = pkgs.writeTextDir "sunsetr.toml" ''
    backend = "auto"
    transition_mode = "static"

    smoothing = false
    startup_duration = 0
    shutdown_duration = 0
    adaptive_interval = 1000

    night_temp = 3300
    day_temp = 6500
    night_gamma = 90
    day_gamma = 100
    update_interval = 300

    static_temp = 3300
    static_gamma = 90

    sunset = "19:00:00"
    sunrise = "06:00:00"
    transition_duration = 45

    latitude = 40.714269
    longitude = -74.005974
  '';
  internalDisplayIgnoredDescriptions = pkgs.writeText "niri-internal-display-auto-off-ignored.json" (
    builtins.toJSON internalDisplayCfg.ignoredOutputDescriptions
  );
  internalDisplayAutoOffScript = pkgs.writeShellScript "niri-internal-display-auto-off" ''
    set -eu

    laptop_output=${lib.escapeShellArg internalDisplayCfg.output}
    ignored_descriptions=${lib.escapeShellArg internalDisplayIgnoredDescriptions}

    enforce_outputs() {
      outputs="$(${niriBin} msg --json outputs 2>/dev/null || true)"
      if [ -z "$outputs" ]; then
        return 0
      fi

      ignored_outputs="$(printf '%s\n' "$outputs" | ${jqBin} -r --slurpfile ignored "$ignored_descriptions" '
        to_entries[]
        | . as $output
        | ([$output.value.make, $output.value.model, ($output.value.serial // "Unknown")] | join(" ")) as $description
        | select($ignored[0] | index($description))
        | $output.key
      ')"

      external_count="$(printf '%s\n' "$outputs" | ${jqBin} -r --arg laptop "$laptop_output" --slurpfile ignored "$ignored_descriptions" '
        [
          to_entries[]
          | . as $output
          | ([$output.value.make, $output.value.model, ($output.value.serial // "Unknown")] | join(" ")) as $description
          | select($output.key != $laptop)
          | select(($ignored[0] | index($description)) | not)
        ]
        | length
      ')"

      laptop_is_on="$(printf '%s\n' "$outputs" | ${jqBin} -r --arg laptop "$laptop_output" '.[$laptop].logical != null')"

      for output in $ignored_outputs; do
        output_is_on="$(printf '%s\n' "$outputs" | ${jqBin} -r --arg output "$output" '.[$output].logical != null')"
        if [ "$output_is_on" = "true" ]; then
          ${niriBin} msg output "$output" off >/dev/null 2>&1 || true
        fi
      done

      if [ "$external_count" -gt 0 ]; then
        if [ "$laptop_is_on" = "true" ]; then
          ${niriBin} msg output "$laptop_output" off >/dev/null 2>&1 || true
        fi
      elif [ "$laptop_is_on" = "false" ]; then
        ${niriBin} msg output "$laptop_output" on >/dev/null 2>&1 || true
      fi
    }

    enforce_outputs

    ${niriBin} msg --json event-stream | while IFS= read -r line; do
      case "$line" in
        *OutputConfigChanged*|*WorkspacesChanged*)
          ${sleepBin} 0.2
          enforce_outputs
          ;;
      esac
    done
  '';
in
{
  options.local.niri.services = {
    enable = lib.mkEnableOption "Desktop services (cliphist, sunsetr, udiskie, workspace OSD)";
    workspaceOsd.enable = lib.mkEnableOption "workspace switch notifications";
    internalDisplayAutoOff = {
      enable = lib.mkEnableOption "automatic internal display disabling when external outputs are connected";
      output = lib.mkOption {
        type = lib.types.str;
        default = "eDP-1";
        description = "Niri output name for the laptop/internal display to toggle.";
      };
      ignoredOutputDescriptions = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = "Output descriptions to disable and ignore when deciding whether an external display is connected.";
      };
    };
  };

  config = lib.mkIf (cfg.enable && cfg.services.enable) {
    # USB auto-mount without a resident tray icon.
    services.udiskie = {
      enable = true;
      tray = "never";
    };

    # Clipboard history watcher
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

    # Night light (color temperature shift)
    systemd.user.services.sunsetr = {
      Unit = {
        Description = "Day/night color temperature adjustment";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${lib.getExe pkgs.sunsetr} --config ${sunsetrConfig}";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.polkit-kde-agent = {
      Unit = {
        Description = "KDE Polkit authentication agent";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.kdePackages.polkit-kde-agent-1}/libexec/polkit-kde-authentication-agent-1";
        Restart = "on-failure";
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    systemd.user.services.niri-internal-display-auto-off = lib.mkIf internalDisplayCfg.enable {
      Unit = {
        Description = "Keep the internal display off while external displays are connected";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${internalDisplayAutoOffScript}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    # Workspace switch OSD
    systemd.user.services.workspace-osd = lib.mkIf cfg.services.workspaceOsd.enable {
      Unit = {
        Description = "Show workspace number on switch";
        PartOf = [ "graphical-session.target" ];
        After = [ "graphical-session.target" ];
      };
      Service = {
        ExecStart = "${pkgs.writeShellScript "workspace-osd" ''
          workspaces='[]'

          niri msg --json event-stream | while IFS= read -r line; do
            case "$line" in
              *WorkspacesChanged*)
                # The event stream sends the full workspace state up front.
                workspaces=$(printf '%s\n' "$line" | ${pkgs.jq}/bin/jq -c '.WorkspacesChanged.workspaces')
                ;;
              *WorkspaceActivated*)
                focused=$(printf '%s\n' "$line" | ${pkgs.jq}/bin/jq -r '.WorkspaceActivated.focused')
                if [ "$focused" = "true" ]; then
                  id=$(printf '%s\n' "$line" | ${pkgs.jq}/bin/jq -r '.WorkspaceActivated.id')
                  idx=$(printf '%s\n' "$workspaces" | ${pkgs.jq}/bin/jq -r --argjson id "$id" '.[] | select(.id == $id) | .idx')

                  if [ -n "$idx" ] && [ "$idx" != "null" ]; then
                    ${pkgs.libnotify}/bin/notify-send -t 800 \
                      -h string:x-canonical-private-synchronous:workspace-osd \
                      "Workspace $idx"
                  fi
                fi
                ;;
            esac
          done
        ''}";
        Restart = "on-failure";
        RestartSec = 3;
      };
      Install.WantedBy = [ "graphical-session.target" ];
    };

    home.packages = with pkgs; [
      grim
      slurp
      satty
      brightnessctl
      playerctl
      oculante
      mpv
      cliphist
      sunsetr
      swaybg
      gpu-screen-recorder
      impala
      pwvucontrol
      papirus-icon-theme
      libnotify
    ];
  };
}
