{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.headroom;
  defaultPackage = pkgs.callPackage ../../packages/headroom-ai.nix { };
  proxyUrl = "http://${cfg.host}:${toString cfg.port}";
  proxyBaseUrl = "${proxyUrl}/v1";

  sessionHelper = pkgs.writeShellApplication {
    name = "headroom-agent-session";
    runtimeInputs = [
      cfg.package
      pkgs.coreutils
      pkgs.curl
      pkgs.gnugrep
      pkgs.gnused
      pkgs.procps
      pkgs.util-linux
    ];
    text = ''
      set -euo pipefail

      if [ "$#" -lt 3 ]; then
        printf 'usage: headroom-agent-session <agent> -- <command> [args...]\n' >&2
        exit 64
      fi

      agent="$1"
      shift
      if [ "$1" != "--" ]; then
        printf 'headroom-agent-session: expected -- after agent name\n' >&2
        exit 64
      fi
      shift

      host="${cfg.host}"
      port="${toString cfg.port}"
      proxy_url="${proxyUrl}"
      runtime_base="''${XDG_RUNTIME_DIR:-/tmp}/headroom-agent-session"
      state_base="''${XDG_STATE_HOME:-$HOME/.local/state}/headroom"
      sessions_dir="$runtime_base/sessions"
      lock_file="$runtime_base/lock"
      pid_file="$runtime_base/proxy.pid"
      log_file="$state_base/proxy.log"
      session_file="$sessions_dir/$agent-$$"

      mkdir -p "$sessions_dir" "$state_base"
      exec 9>"$lock_file"

      lock() {
        flock 9
      }

      unlock() {
        flock -u 9
      }

      proxy_healthy() {
        curl --silent --fail --max-time 1 "$proxy_url/health" >/dev/null 2>&1
      }

      pid_alive() {
        [ -n "''${1:-}" ] && kill -0 "$1" 2>/dev/null
      }

      cleanup_stale_sessions() {
        for file in "$sessions_dir"/*; do
          [ -e "$file" ] || continue
          pid="$(sed -n 's/^pid=//p' "$file" 2>/dev/null | head -n1)"
          if ! pid_alive "$pid"; then
            rm -f "$file"
          fi
        done
      }

      has_live_sessions() {
        for file in "$sessions_dir"/*; do
          [ -e "$file" ] || continue
          return 0
        done
        return 1
      }

      start_proxy_if_needed() {
        lock
        cleanup_stale_sessions

        if proxy_healthy; then
          unlock
          return 0
        fi

        if [ -e "$pid_file" ]; then
          old_pid="$(cat "$pid_file" 2>/dev/null || true)"
          if pid_alive "$old_pid"; then
            unlock
            printf 'headroom proxy pid %s is running but %s/health is not healthy; see %s\n' "$old_pid" "$proxy_url" "$log_file" >&2
            exit 1
          fi
          rm -f "$pid_file"
        fi

        : > "$log_file"
        HEADROOM_TELEMETRY=off headroom proxy --host "$host" --port "$port" >>"$log_file" 2>&1 &
        proxy_pid="$!"
        printf '%s\n' "$proxy_pid" > "$pid_file"

        for _ in $(seq 1 45); do
          if proxy_healthy; then
            unlock
            return 0
          fi
          if ! pid_alive "$proxy_pid"; then
            unlock
            printf 'headroom proxy exited before becoming healthy; see %s\n' "$log_file" >&2
            exit 1
          fi
          sleep 1
        done

        kill "$proxy_pid" 2>/dev/null || true
        rm -f "$pid_file"
        unlock
        printf 'headroom proxy did not become healthy within 45 seconds; see %s\n' "$log_file" >&2
        exit 1
      }

      cleanup() {
        status="$?"
        set +e
        lock
        rm -f "$session_file"
        cleanup_stale_sessions

        if ! has_live_sessions && [ -e "$pid_file" ]; then
          proxy_pid="$(cat "$pid_file" 2>/dev/null || true)"
          if pid_alive "$proxy_pid"; then
            kill "$proxy_pid" 2>/dev/null || true
          fi
          rm -f "$pid_file"
        fi

        unlock
        exit "$status"
      }

      printf 'pid=%s\nagent=%s\n' "$$" "$agent" > "$session_file"
      trap cleanup EXIT INT TERM

      start_proxy_if_needed
      "$@"
    '';
  };
in
{
  options.local.headroom = {
    enable = lib.mkEnableOption "Headroom AI CLI proxy integration";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      description = "Headroom package used by the proxy session helper.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Host for the on-demand Headroom proxy.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Port for the on-demand Headroom proxy.";
    };

    agents = lib.mkOption {
      type = lib.types.attrsOf lib.types.bool;
      default = {
        antigravity = true;
        codex = true;
        gemini = true;
        opencode = true;
      };
      description = "AI CLI wrappers to route through Headroom when their modules are enabled.";
    };

    sessionHelper = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      default = sessionHelper;
      description = "Reference-counted helper used by AI CLI modules.";
    };

    proxyUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = proxyUrl;
      description = "Base Headroom proxy URL without /v1.";
    };

    proxyBaseUrl = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = proxyBaseUrl;
      description = "OpenAI-compatible Headroom proxy base URL.";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [
      cfg.package
      sessionHelper
    ];
  };
}
