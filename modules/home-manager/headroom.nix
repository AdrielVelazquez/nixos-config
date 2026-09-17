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

  # HEADROOM_* proxy tuning knobs exported by the wrapper. Output-shaper knobs
  # are hot-reloaded onto a reused proxy via /admin/runtime-env; mode,
  # target-ratio, lossless and the rollout channel are startup-only. A beta
  # output-shaper trial requires a fresh proxy started in that channel.
  tuningEnv = {
    HEADROOM_MODE = cfg.tuning.mode;
  }
  // lib.optionalAttrs (cfg.tuning.targetRatio != null) {
    HEADROOM_TARGET_RATIO = toString cfg.tuning.targetRatio;
  }
  // lib.optionalAttrs cfg.tuning.lossless { HEADROOM_LOSSLESS = "1"; }
  // lib.optionalAttrs cfg.tuning.reduceOutputTokens {
    HEADROOM_OUTPUT_SHAPER = "1";
    HEADROOM_EFFORT_ROUTER = "1";
    HEADROOM_VERBOSITY_AUTOTUNE = "1";
  }
  // lib.optionalAttrs (cfg.tuning.verbosityLevel != null) {
    HEADROOM_VERBOSITY_LEVEL = toString cfg.tuning.verbosityLevel;
  }
  // cfg.proxyEnv;

  # Respect an explicit environment override; otherwise apply the module value.
  mkTuningExport = name: value: ''export ${name}="''${${name}:-${value}}"'';
  tuningEnvExports = lib.concatStringsSep "\n          " (
    lib.mapAttrsToList mkTuningExport tuningEnv
  );

  opencodeV2Launcher = pkgs.writeShellScriptBin "opencode" ''
    exec ${pkgs.python3.interpreter} ${../../packages/headroom-opencode-v2.py} \
      "$HEADROOM_OPENCODE_REAL_BIN" "$@"
  '';

  headroom =
    (pkgs.writeShellApplication {
      name = "headroom";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.uv
      ];
      text = ''
          export HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS="''${HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS:-${toString cfg.codexWsCompressionTimeoutSeconds}}"
          ${tuningEnvExports}

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
              export HEADROOM_OPENCODE_REAL_BIN
              HEADROOM_OPENCODE_REAL_BIN="''${HEADROOM_OPENCODE_REAL_BIN:-$(command -v opencode)}"
              export HEADROOM_OPENCODE_WRAPPED=1
              export HEADROOM_OPENCODE_NO_SERENA=0
              for argument in "$@"; do
                [ "$argument" = "--" ] && break
                if [ "$argument" = "--no-serena" ]; then
                  HEADROOM_OPENCODE_NO_SERENA=1
                fi
              done
              # Suppress the upstream plugin, which only supports OpenCode v1.
              export HEADROOM_OPENCODE_PLUGIN_PATH="$session_dir/no-v1-plugin"
              export HEADROOM_OPENCODE_LAUNCHER_DIR="${opencodeV2Launcher}/bin"
              export PATH="${opencodeV2Launcher}/bin:$PATH"
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
    package = lib.mkOption {
      type = lib.types.package;
      default = headroom;
      readOnly = true;
      internal = true;
      description = "Configured Headroom launcher for other managed CLIs.";
    };
    enable = lib.mkEnableOption "Headroom CLI";
    codexWsCompressionTimeoutSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 30;
      description = ''
        Default Codex WebSocket compression deadline in seconds. An explicit
        HEADROOM_CODEX_WS_COMPRESSION_TIMEOUT_SECONDS environment variable
        overrides this value; the general compression deadline still applies.
      '';
    };
    wrapDefaults = {
      memory = lib.mkEnableOption "persistent memory for Codex and OpenCode Headroom wraps";
      codeGraph = lib.mkEnableOption "code-graph indexing for Codex and OpenCode Headroom wraps";
      port = lib.mkOption {
        type = lib.types.port;
        default = 8787;
        description = "Default shared proxy port for Codex and OpenCode Headroom wraps";
      };
    };
    tuning = {
      mode = lib.mkOption {
        type = lib.types.enum [
          "cache"
          "token"
        ];
        default = "cache";
        description = ''
          Proxy optimization mode (HEADROOM_MODE). "cache" freezes prior turns
          to maximize provider prefix-cache hits (best dollar cost on backends
          with prompt caching, e.g. direct Anthropic). "token" rewrites history
          for maximum raw token compression but breaks prefix caching. This is a
          startup-only knob: a shared proxy that is already running will be
          reused as-is, so a mode change only takes effect when the proxy next
          starts cold.
        '';
      };
      targetRatio = lib.mkOption {
        type = lib.types.nullOr (lib.types.either lib.types.float lib.types.int);
        default = null;
        description = ''
          Override Kompress keep-ratio for text compression (HEADROOM_TARGET_RATIO).
          Lower is more aggressive (e.g. 0.4 keeps ~40% of tokens). Null lets
          Kompress decide conservatively. Startup-only, like mode.
        '';
      };
      lossless = lib.mkEnableOption ''
        lossless-only tool-output compaction without CCR markers or retrieval
        tool injection (HEADROOM_LOSSLESS). This restricts the normal compression
        pipeline rather than adding another savings layer. Startup-only, like mode'';
      reduceOutputTokens = lib.mkEnableOption ''
        output-token shaping (HEADROOM_OUTPUT_SHAPER + HEADROOM_EFFORT_ROUTER +
        HEADROOM_VERBOSITY_AUTOTUNE). The bundled effort and autotune defaults can
        be overridden independently with proxyEnv. Headroom 0.37.0 requires
        HEADROOM_ROLLOUT_CHANNEL=beta or higher at proxy startup; shaping knobs
        can then be hot-reloaded via /admin/runtime-env. Measure output and
        provider cache usage together to assess cost'';
      verbosityLevel = lib.mkOption {
        type = lib.types.nullOr (lib.types.ints.between 0 4);
        default = null;
        description = ''
          Fixed verbosity steering level 0-4 (HEADROOM_VERBOSITY_LEVEL). Higher
          levels request terser output; zero disables prompt steering. Null
          defers to the autotune controller / learned default. Only meaningful
          when reduceOutputTokens is enabled.
        '';
      };
    };
    proxyEnv = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        HEADROOM_MECHANICAL_EFFORT = "minimal";
      };
      description = ''
        Escape hatch for additional HEADROOM_* proxy environment variables
        exported by the wrapper. Values here override the typed tuning options.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ headroom ];
  };
}
