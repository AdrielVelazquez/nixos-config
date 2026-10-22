{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.headroom.pi;
  common = config.local.headroom;
  adapters = lib.mapAttrsToList (provider: adapter: adapter // { inherit provider; }) cfg.adapters;
  upstream = lib.unique (lib.concatMap (adapter: adapter.upstreamOrigins) adapters);
  tokenizerCache = pkgs.callPackage ../../packages/headroom-tokenizer-cache.nix { };
  tuning = {
    HEADROOM_MODE = common.tuning.mode;
    TIKTOKEN_CACHE_DIR = toString tokenizerCache;
  }
  // lib.optionalAttrs (common.tuning.targetRatio != null) {
    HEADROOM_TARGET_RATIO = toString common.tuning.targetRatio;
  }
  // lib.optionalAttrs common.tuning.lossless { HEADROOM_LOSSLESS = "1"; }
  // lib.optionalAttrs common.tuning.reduceOutputTokens {
    HEADROOM_OUTPUT_SHAPER = "1";
    HEADROOM_EFFORT_ROUTER = "1";
    HEADROOM_VERBOSITY_AUTOTUNE = "1";
  }
  // lib.optionalAttrs (common.tuning.verbosityLevel != null) {
    HEADROOM_VERBOSITY_LEVEL = toString common.tuning.verbosityLevel;
  }
  // builtins.removeAttrs common.proxyEnv [ "HEADROOM_ALLOWED_BASE_URLS" ];
  manifest = pkgs.writeText "headroom-pi.json" (
    builtins.toJSON {
      version = 1;
      implementation = toString ../../packages/headroom-pi.py;
      piCommand = [ (lib.getExe config.local.pi.package) ];
      proxyCommand = [ (lib.getExe common.package) ];
      gitCommand = lib.getExe pkgs.git;
      user = config.home.username;
      inherit adapters;
      upstreamOrigins = upstream;
      tuningEnv = tuning;
      port = cfg.port;
      startupTimeout = cfg.startupTimeout;
      memory = cfg.memory;
      codeGraph = cfg.codeGraph;
      extraPath = lib.optional cfg.codeGraph "${pkgs.codebase-memory-mcp}/bin";
    }
  );
  launcher = pkgs.writeShellScriptBin "pi" ''
    exec ${pkgs.python3.interpreter} -E ${../../packages/headroom-pi.py} --config ${manifest} -- "$@"
  '';
  rawHeadroom = common.package.unwrapped;
  memoryPythonPath =
    "${rawHeadroom}/${pkgs.python3.sitePackages}:"
    + pkgs.python3Packages.makePythonPath (
      pkgs.python3Packages.requiredPythonModules rawHeadroom.dependencies
    );
  memoryServer = pkgs.writeShellScript "pi-headroom-memory" ''
    : "''${HEADROOM_PI_MEMORY_DB:?Start Pi through the Headroom launcher}"
    exec ${pkgs.coreutils}/bin/env -u PYTHONHOME PYTHONPATH=${lib.escapeShellArg memoryPythonPath} \
      HF_HUB_CACHE=${
        pkgs.callPackage ../../packages/headroom-memory-model.nix { }
      } HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1 \
      ${pkgs.python3.interpreter} -m headroom.memory.mcp_server --db "$HEADROOM_PI_MEMORY_DB" --user ${lib.escapeShellArg config.home.username}
  '';
  serenaServer = pkgs.writeShellScript "pi-serena" ''
    exec ${pkgs.coreutils}/bin/env -u PYTHONPATH -u PYTHONHOME \
      ${pkgs.uv}/bin/uvx --from serena-agent serena start-mcp-server \
      --project-from-cwd --context claude-code --agent-interface tools --open-web-dashboard False
  '';
in
{
  options.local.headroom.pi = {
    enable = lib.mkEnableOption "session-owned Headroom inference and MCPs for Pi";
    port = lib.mkOption {
      type = lib.types.port;
      default = 0;
      description = "Zero allocates an owned loopback port per compatible project session family.";
    };
    startupTimeout = lib.mkOption {
      type = lib.types.ints.positive;
      default = 90;
    };
    memory = lib.mkOption {
      type = lib.types.bool;
      default = common.wrapDefaults.memory;
    };
    codeGraph = lib.mkOption {
      type = lib.types.bool;
      default = common.wrapDefaults.codeGraph;
    };
    serena.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
    };
    adapters = lib.mkOption {
      default = { };
      description = "Provider-owned, fail-closed inference-proxy contracts; no unsupported provider is silently declared compressed.";
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            urlEnv = lib.mkOption { type = lib.types.strMatching "[A-Z][A-Z0-9_]*"; };
            requiredEnv = lib.mkOption { type = lib.types.strMatching "[A-Z][A-Z0-9_]*"; };
            upstreamOrigins = lib.mkOption { type = lib.types.listOf lib.types.str; };
          };
        }
      );
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    assertions = [
      {
        assertion = common.enable;
        message = "Pi's Headroom integration requires local.headroom.enable";
      }
      {
        assertion = adapters != [ ];
        message = "Enable a supported Pi inference-proxy adapter before enabling Headroom/Pi";
      }
      {
        assertion = pkgs.stdenv.hostPlatform.isLinux;
        message = "Headroom/Pi process-identity validation currently supports Linux";
      }
    ];
    local.pi.launcher = launcher;
    local.pi.extraSettings.extensions = [ "${../../dotfiles/pi/extensions/headroom.ts}" ];
    local.pi.requiredChildExtensions = [
      {
        id = "headroom";
        path = "${../../dotfiles/pi/extensions/headroom.ts}";
      }
    ];
    local.pi.mcpServers = {
      headroom = {
        command = lib.getExe common.package;
        args = [
          "mcp"
          "serve"
        ];
        env.HEADROOM_PROXY_URL = "\${HEADROOM_PROXY_URL}";
        env.TIKTOKEN_CACHE_DIR = toString tokenizerCache;
        toolExposure.headroom_stats = "direct";
      };
    }
    // lib.optionalAttrs cfg.memory {
      headroom_memory = {
        command = toString memoryServer;
      };
    }
    // lib.optionalAttrs cfg.serena.enable {
      serena = {
        command = toString serenaServer;
      };
    };
    programs.pi-coding-agent.context = lib.optionalString cfg.memory ''
      # Headroom memory
      Use the headroom_memory MCP server for persistent project knowledge.
      Search relevant memory before relying on prior decisions; save useful durable
      facts after verified work. Never store secrets. Tool names are native Pi MCP
      names: discover the server's memory_search/memory_save operations when needed.
    '';
  };
}
