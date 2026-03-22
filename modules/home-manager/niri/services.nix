# modules/home-manager/niri/services.nix
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
  options.local.niri.services.enable =
    lib.mkEnableOption "Desktop services (cliphist, wlsunset, udiskie, workspace OSD)";

  config = lib.mkIf (cfg.enable && cfg.services.enable) {
    # USB auto-mount with tray icon
    services.udiskie = {
      enable = true;
      tray = "auto";
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

    # Workspace switch OSD
    systemd.user.services.workspace-osd = {
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
      swww
      grim
      slurp
      satty
      brightnessctl
      playerctl
      yazi
      oculante
      mpv
      cliphist
      wlsunset
      gpu-screen-recorder
      impala
      pwvucontrol
      papirus-icon-theme
      libnotify
    ];
  };
}
