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
    user_machine="adriel@.host"
    state_file="/run/openrazer-daemon.was-active"

    case "$1" in
      pre)
        if ${pkgs.systemd}/bin/systemctl --user -M "$user_machine" --quiet is-active "$service"; then
          if ${pkgs.systemd}/bin/systemctl --user -M "$user_machine" stop "$service"; then
            ${pkgs.coreutils}/bin/touch "$state_file"
          else
            ${pkgs.coreutils}/bin/rm -f "$state_file"
          fi
        else
          ${pkgs.coreutils}/bin/rm -f "$state_file"
        fi
        ;;
      post)
        if [ -e "$state_file" ]; then
          ${pkgs.systemd}/bin/systemctl --user -M "$user_machine" start "$service" || true
          ${pkgs.coreutils}/bin/rm -f "$state_file"
        fi
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
