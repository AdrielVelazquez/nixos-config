# modules/home-manager/niri/ironbar.nix
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
  options.local.niri.ironbar.enable = lib.mkEnableOption "Ironbar status bar";

  config = lib.mkIf (cfg.enable && cfg.ironbar.enable) {
    programs.ironbar = {
      enable = true;
      systemd = true;

      config = {
        name = "main";
        position = "top";
        anchor_to_edges = true;
        height = 36;
        autohide = 1500;
        exclusive_zone = true;

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
            type = "script";
            cmd = "${pkgs.writeShellScript "nvidia-status" ''
              state=$(cat /sys/bus/pci/devices/0000:c4:00.0/power_state)
              case "$state" in
                D3cold) echo '<span color="#6c7086">󰍹</span>' ;;
                D3hot)  echo '<span color="#f9e2af">󰍹</span>' ;;
                *)      echo '<span color="#f38ba8">󰍹</span>' ;;
              esac
            ''}";
            mode = "poll";
            interval = 60000;
            class = "nvidia-status";
          }
          ++ [
            {
              type = "script";
              cmd = "${pkgs.writeShellScript "power-profile-watch" ''
                show() {
                  case "$(powerprofilesctl get 2>/dev/null)" in
                  performance) echo "" ;;
                  balanced)    echo "" ;;
                  power-saver) echo "" ;;
                  *)           echo "" ;;
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
              type = "script";
              cmd = "${pkgs.writeShellScript "wifi-status" ''
                ssid=$(${pkgs.iw}/bin/iw dev wlan0 link 2>/dev/null | grep SSID | awk '{print $2}')
                if [ -n "$ssid" ]; then
                  signal=$(${pkgs.iw}/bin/iw dev wlan0 link 2>/dev/null | grep signal | awk '{print $2}')
                  if [ "$signal" -ge -50 ] 2>/dev/null; then
                    echo "󰤨"
                  elif [ "$signal" -ge -70 ] 2>/dev/null; then
                    echo "󰤥"
                  else
                    echo "󰤟"
                  fi
                else
                  echo "<span color='#6c7086'>󰤭</span>"
                fi
              ''}";
              mode = "poll";
              interval = 10000;
              class = "wifi";
              on_click_left = "kitty @ --to unix:$(ls /tmp/kitty-* 2>/dev/null | head -n1) launch --type=tab --tab-title Network nmtui || kitty nmtui";
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
              type = "script";
              cmd = "${pkgs.writeShellScript "battery-status" ''
                capacity=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
                status=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
                [ -z "$capacity" ] && exit 0
                if [ "$status" = "Charging" ]; then
                  echo " $capacity%"
                elif [ "$capacity" -ge 90 ]; then
                  echo " $capacity%"
                elif [ "$capacity" -ge 60 ]; then
                  echo " $capacity%"
                elif [ "$capacity" -ge 40 ]; then
                  echo " $capacity%"
                elif [ "$capacity" -ge 15 ]; then
                  echo "<span color='#f9e2af'> $capacity%</span>"
                else
                  echo "<span color='#f38ba8'> $capacity%</span>"
                fi
              ''}";
              mode = "poll";
              interval = 30000;
              class = "battery";
            }
            {
              type = "tray";
            }
          ];
      };

      style = ''
        @define-color bg rgba(0, 0, 0, 0.7);
        @define-color fg #cdd6f4;
        @define-color accent #5a9cbf;

        * {
          font-family: "Maple Mono NF", monospace;
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
          color: #6c7086;
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

        .battery.warning label {
          color: #f9e2af;
        }

        .battery.critical label {
          color: #f38ba8;
        }
      '';
    };
  };
}
