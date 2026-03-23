{
  pkgs,
  ...
}:
let
  sleepTargets = [
    "systemd-suspend.service"
    "systemd-hibernate.service"
    "systemd-hybrid-sleep.service"
    "systemd-suspend-then-hibernate.service"
  ];

  openrazerSleepHook = pkgs.writeShellScript "openrazer-sleep-hook" ''
    set -eu

    service="openrazer-daemon.service"
    user="adriel"
    state_file="/run/openrazer-daemon.was-active"
    uid="$(${pkgs.coreutils}/bin/id -u "$user")"
    gid="$(${pkgs.coreutils}/bin/id -g "$user")"
    runtime_dir="/run/user/$uid"
    bus_address="unix:path=$runtime_dir/bus"

    user_systemctl() {
      ${pkgs.util-linux}/bin/setpriv \
        --reuid "$uid" \
        --regid "$gid" \
        --init-groups \
        ${pkgs.coreutils}/bin/env \
          XDG_RUNTIME_DIR="$runtime_dir" \
          DBUS_SESSION_BUS_ADDRESS="$bus_address" \
          ${pkgs.systemd}/bin/systemctl --user "$@"
    }

    wait_for_user_bus() {
      i=0
      while [ "$i" -lt 20 ]; do
        if [ -S "$runtime_dir/bus" ]; then
          return 0
        fi
        ${pkgs.coreutils}/bin/sleep 0.25
        i=$((i + 1))
      done
      return 1
    }

    case "$1" in
      pre)
        if wait_for_user_bus && user_systemctl --quiet is-active "$service"; then
          if user_systemctl stop "$service"; then
            ${pkgs.coreutils}/bin/touch "$state_file"
          else
            ${pkgs.coreutils}/bin/rm -f "$state_file"
          fi
        else
          ${pkgs.coreutils}/bin/rm -f "$state_file"
        fi
        ;;
      post)
        if [ -e "$state_file" ] && wait_for_user_bus; then
          user_systemctl start "$service" || true
        fi
        ${pkgs.coreutils}/bin/rm -f "$state_file"
        ;;
      *)
        exit 1
        ;;
    esac
  '';
in
{
  # Stop the user daemon before sleep so the internal Razer USB device can idle.
  systemd.services.openrazer-pre-sleep = {
    description = "Stop OpenRazer daemon before sleep";
    wantedBy = sleepTargets;
    before = sleepTargets;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${openrazerSleepHook} pre";
    };
  };

  systemd.services.openrazer-post-sleep = {
    description = "Restart OpenRazer daemon after sleep";
    wantedBy = sleepTargets;
    after = sleepTargets;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${openrazerSleepHook} post";
    };
  };
}
