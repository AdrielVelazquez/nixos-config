{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.headroom;
  upstreamHeadroom = pkgs.callPackage ../../packages/headroom-ai.nix { };
  defaultWrapFlags =
    lib.optionals cfg.wrapDefaults.memory [ "--memory" ]
    ++ lib.optionals cfg.wrapDefaults.codeGraph [ "--code-graph" ];

  headroom =
    (pkgs.writeShellApplication {
      name = "headroom";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.uv
      ];
      text = ''
          if [ "$#" -lt 2 ] || [ "$1" != "wrap" ]; then
            exec ${upstreamHeadroom}/bin/headroom "$@"
          fi

          case "$2" in
            codex | opencode) ;;
            *) exec ${upstreamHeadroom}/bin/headroom "$@" ;;
          esac

        wrap_target="$2"
        headroom_args=("$1" "$wrap_target")
        shift 2
        for default_flag in ${lib.escapeShellArgs defaultWrapFlags}; do
          flag_present=0
          for argument in "$@"; do
            [ "$argument" = "--" ] && break
            if [ "$argument" = "$default_flag" ]; then
              flag_present=1
              break
            fi
          done
          if [ "$flag_present" -eq 0 ]; then
            headroom_args+=("$default_flag")
          fi
        done
        port_present=0
        for argument in "$@"; do
          case "$argument" in
            --) break ;;
            --port | -p | --port=* | -p=*)
              port_present=1
              break
              ;;
          esac
        done
        if [ "$port_present" -eq 0 ]; then
          headroom_args+=("--port" "${toString cfg.wrapDefaults.port}")
        fi
        headroom_args+=("$@")

          if [ "$wrap_target" = "codex" ]; then
            exec ${upstreamHeadroom}/bin/headroom "''${headroom_args[@]}"
          fi

              config_root="''${XDG_CONFIG_HOME:-$HOME/.config}"
              source_config="''${OPENCODE_CONFIG:-$config_root/opencode/opencode.json}"
              runtime_root="''${XDG_RUNTIME_DIR:-''${TMPDIR:-/tmp}}"
              session_dir="$(${pkgs.coreutils}/bin/mktemp -d "$runtime_root/headroom-opencode.XXXXXXXX")"
              session_config="$session_dir/opencode.json"

              cleanup() {
                ${pkgs.coreutils}/bin/rm -rf -- "$session_dir"
              }
              trap cleanup EXIT

              if [ -e "$source_config" ]; then
                ${pkgs.coreutils}/bin/install -m 600 "$source_config" "$session_config"
              else
                ${pkgs.coreutils}/bin/install -m 600 /dev/null "$session_config"
              fi

              export OPENCODE_CONFIG="$session_config"
            ${upstreamHeadroom}/bin/headroom "''${headroom_args[@]}"
      '';
    }).overrideAttrs
      (previous: {
        pname = upstreamHeadroom.pname;
        inherit (upstreamHeadroom) version meta;
        passthru = (previous.passthru or { }) // {
          unwrapped = upstreamHeadroom;
        };
      });
in
{
  options.local.headroom = {
    enable = lib.mkEnableOption "Headroom CLI";
    wrapDefaults = {
      memory = lib.mkEnableOption "persistent memory for Codex and OpenCode Headroom wraps";
      codeGraph = lib.mkEnableOption "code-graph indexing for Codex and OpenCode Headroom wraps";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8787;
        description = "Default shared proxy port for Codex and OpenCode Headroom wraps";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ headroom ];
  };
}
