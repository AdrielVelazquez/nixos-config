# modules/system/display-power.nix
# Automatically adjust display refresh rate based on power state
#
# Lower refresh rate on battery saves significant power.
# Example: 120Hz → 60Hz can save 1-3W on modern panels.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.within.display-power;

  # Parse resolution string "2880x1800" into width and height
  resolutionParts = lib.splitString "x" cfg.displayResolution;
  width = builtins.elemAt resolutionParts 0;
  height = builtins.elemAt resolutionParts 1;

  # Get the appropriate tool based on display server
  displayTool =
    {
      cosmic = "${pkgs.cosmic-randr}/bin/cosmic-randr";
      gnome = "${pkgs.gnome-randr}/bin/gnome-randr";
      hyprland = "${pkgs.hyprland}/bin/hyprctl";
      sway = "${pkgs.sway}/bin/swaymsg";
      kde = "${pkgs.kdePackages.libkscreen}/bin/kscreen-doctor";
      x11 = "${pkgs.xorg.xrandr}/bin/xrandr";
    }
    .${cfg.displayServer};

  # Script to change refresh rate based on power state
  refreshRateScript = pkgs.writeShellScript "set-refresh-rate" ''
    set -euo pipefail

    # Get current power state
    # Returns "Charging", "Discharging", "Full", "Not charging", etc.
    POWER_STATE=$(cat /sys/class/power_supply/*/status 2>/dev/null | head -1 || echo "Unknown")

    # Determine target refresh rate
    if [[ "$POWER_STATE" == "Discharging" ]]; then
      TARGET_RATE="${toString cfg.batteryRefreshRate}"
      MODE="battery"
    else
      TARGET_RATE="${toString cfg.acRefreshRate}"
      MODE="plugged"
    fi

    echo "Power state: $POWER_STATE, setting refresh rate to ''${TARGET_RATE}Hz ($MODE mode)"

    # Apply based on display server
    case "${cfg.displayServer}" in
      cosmic)
        # COSMIC desktop uses cosmic-randr
        # cosmic-randr mode <OUTPUT> <WIDTH> <HEIGHT> --refresh <RATE>
        for user in $(who | awk '{print $1}' | sort -u); do
          uid=$(id -u "$user" 2>/dev/null || continue)
          export XDG_RUNTIME_DIR="/run/user/$uid"
          export WAYLAND_DISPLAY="wayland-1"
          
          sudo -u "$user" ${displayTool} mode \
            "${cfg.displayName}" ${width} ${height} \
            --refresh "$TARGET_RATE" 2>/dev/null || true
        done
        ;;

      gnome)
        # GNOME uses gnome-randr
        for user in $(who | awk '{print $1}' | sort -u); do
          uid=$(id -u "$user" 2>/dev/null || continue)
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
          
          sudo -u "$user" ${displayTool} modify \
            "${cfg.displayName}" --rate "$TARGET_RATE" 2>/dev/null || true
        done
        ;;
      
      hyprland)
        # Hyprland uses hyprctl
        for user in $(who | awk '{print $1}' | sort -u); do
          uid=$(id -u "$user" 2>/dev/null || continue)
          export HYPRLAND_INSTANCE_SIGNATURE=$(ls /tmp/hypr/ 2>/dev/null | head -1 || echo "")
          if [[ -n "$HYPRLAND_INSTANCE_SIGNATURE" ]]; then
            sudo -u "$user" ${displayTool} keyword monitor \
              "${cfg.displayName},preferred,auto,$TARGET_RATE" 2>/dev/null || true
          fi
        done
        ;;
      
      sway)
        # Sway uses swaymsg
        for user in $(who | awk '{print $1}' | sort -u); do
          uid=$(id -u "$user" 2>/dev/null || continue)
          export SWAYSOCK="/run/user/$uid/sway-ipc.$uid.*.sock"
          sudo -u "$user" ${displayTool} output \
            "${cfg.displayName}" mode --custom "${cfg.displayResolution}@''${TARGET_RATE}Hz" 2>/dev/null || true
        done
        ;;
      
      kde)
        # KDE Plasma uses kscreen-doctor
        for user in $(who | awk '{print $1}' | sort -u); do
          uid=$(id -u "$user" 2>/dev/null || continue)
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$uid/bus"
          sudo -u "$user" ${displayTool} \
            output."${cfg.displayName}".mode."${cfg.displayResolution}@$TARGET_RATE" 2>/dev/null || true
        done
        ;;
      
      x11)
        # X11 uses xrandr
        for user in $(who | awk '{print $1}' | sort -u); do
          export DISPLAY=":0"
          export XAUTHORITY="/home/$user/.Xauthority"
          sudo -u "$user" ${displayTool} \
            --output "${cfg.displayName}" --rate "$TARGET_RATE" 2>/dev/null || true
        done
        ;;
      
      *)
        echo "Unknown display server: ${cfg.displayServer}"
        exit 1
        ;;
    esac
  '';

in
{
  options.within.display-power = {
    enable = lib.mkEnableOption "automatic display refresh rate based on power state";

    displayServer = lib.mkOption {
      type = lib.types.enum [
        "cosmic"
        "gnome"
        "hyprland"
        "sway"
        "kde"
        "x11"
      ];
      default = "cosmic";
      description = "Display server/compositor in use";
    };

    displayName = lib.mkOption {
      type = lib.types.str;
      default = "eDP-1";
      description = "Display output name (run `cosmic-randr list` to find)";
    };

    displayResolution = lib.mkOption {
      type = lib.types.str;
      default = "2880x1800";
      description = "Display resolution in WIDTHxHEIGHT format";
    };

    batteryRefreshRate = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Refresh rate (Hz) when on battery";
    };

    acRefreshRate = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = "Refresh rate (Hz) when on AC power";
    };
  };

  config = lib.mkIf cfg.enable {
    # udev rule to trigger on power state changes
    services.udev.extraRules = ''
      # Trigger refresh rate change on AC adapter state change
      SUBSYSTEM=="power_supply", ATTR{type}=="Mains", RUN+="${refreshRateScript}"
    '';

    # Also run on boot/resume to set initial state
    systemd.services.display-power-init = {
      description = "Set display refresh rate based on power state";
      wantedBy = [ "graphical.target" ];
      after = [ "graphical.target" ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = refreshRateScript;
        # Delay to ensure display server is ready
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
      };
    };

    # Run after resume from suspend
    systemd.services.display-power-resume = {
      description = "Set display refresh rate after resume";
      wantedBy = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      after = [
        "suspend.target"
        "hibernate.target"
        "hybrid-sleep.target"
      ];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = refreshRateScript;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 3";
      };
    };
  };
}
