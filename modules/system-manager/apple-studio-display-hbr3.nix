# Force the Apple Studio Display DP link away from the HBR2+DSC path.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.apple-studio-display-hbr3;

  script = pkgs.writeShellScript "apple-studio-display-hbr3-link-watch" ''
    set -euo pipefail

    export PATH="${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.findutils
        pkgs.gnugrep
      ]
    }"

    connector=${lib.escapeShellArg (lib.optionalString (cfg.connector != null) cfg.connector)}
    desired="${cfg.linkSettings}"

    log() {
      printf 'apple-studio-display-hbr3: %s\n' "$*"
    }

    apply_link_settings() {
      local path="$1"
      local settings

      [ -e "$path" ] || return 1

      settings="$(tr -d '\000' < "$path" 2>/dev/null || true)"
      [ -n "$settings" ] || return 1

      if ! printf '%s\n' "$settings" | grep -Eq '(Verified|Reported):[[:space:]]+4[[:space:]]+0x1e'; then
        return 1
      fi

      if printf '%s\n' "$settings" | grep -Eq 'Current:[[:space:]]+4[[:space:]]+0x1e'; then
        return 0
      fi

      if printf '%s\n' "$settings" | grep -Eq 'Current:[[:space:]]+0[[:space:]]+0x0[[:space:]]+0' \
        && printf '%s\n' "$settings" | grep -Eq 'Preferred:[[:space:]]+4[[:space:]]+0x1e'; then
        return 0
      fi

      log "forcing HBR3 on $path"
      if ! printf '%s\n' "$desired" > "$path" 2>/dev/null; then
        log "failed to write $path"
        return 1
      fi
    }

    find_link_settings_paths() {
      if [ -n "$connector" ]; then
        find /sys/kernel/debug/dri -path "*/$connector/link_settings" -print 2>/dev/null
      else
        find /sys/kernel/debug/dri -path '*/DP-*/link_settings' -print 2>/dev/null
      fi
    }

    while true; do
      while IFS= read -r path; do
        apply_link_settings "$path" || true
      done < <(find_link_settings_paths)

      sleep "${toString cfg.intervalSeconds}"
    done
  '';
in
{
  options.local.apple-studio-display-hbr3 = {
    enable = lib.mkEnableOption "Apple Studio Display HBR3 link stabilization";

    connector = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "DP-7";
      description = "Optional DRM connector name for the Apple Studio Display output. When null, scan all DP connectors to survive USB4 connector renumbering.";
    };

    linkSettings = lib.mkOption {
      type = lib.types.str;
      default = "4 0x1e";
      description = "Debugfs link_settings value used to prefer four-lane HBR3.";
    };

    intervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = "How often to re-check the connector's debugfs link settings.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.apple-studio-display-hbr3 = {
      description = "Prefer HBR3 for Apple Studio Display";
      after = [ "sys-kernel-debug.mount" ];

      unitConfig.RequiresMountsFor = "/sys/kernel/debug";

      serviceConfig = {
        Type = "simple";
        ExecStart = script;
        Restart = "always";
        RestartSec = "2s";
      };

      wantedBy = [ "multi-user.target" ];
    };
  };
}
