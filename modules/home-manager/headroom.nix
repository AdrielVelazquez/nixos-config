{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.headroom;

  defaultPackage = pkgs.callPackage ../../packages/headroom-ai.nix { };

  defaultEnvironment = {
    HEADROOM_MODE = "token";
    HEADROOM_SAVINGS_PROFILE = "agent-90";
    HEADROOM_SAVINGS_TARGET = "0.90";
    HEADROOM_TARGET_RATIO = "0.10";
    HEADROOM_COMPRESS_USER_MESSAGES = "1";
    HEADROOM_COMPRESS_SYSTEM_MESSAGES = "1";
    HEADROOM_PROTECT_RECENT = "2";
    HEADROOM_PROTECT_ANALYSIS_CONTEXT = "1";
    HEADROOM_MIN_TOKENS = "120";
    HEADROOM_MAX_ITEMS = "8";
    HEADROOM_FORCE_KOMPRESS = "1";
    HEADROOM_ACCURACY_GUARD = "strict";
  };

  logDir = "${cfg.stateDir}/logs";
  logFile = "${logDir}/proxy.log";

  proxyArgs = [
    "proxy"
    "--host"
    cfg.host
    "--port"
    (toString cfg.port)
    "--mode"
    cfg.mode
    "--intercept-tool-results"
    "--code-aware"
    "--memory"
    "--memory-storage=project"
    "--log-file"
    logFile
  ]
  ++ cfg.extraArgs;
in
{
  options.local.headroom = {
    enable = lib.mkEnableOption "Headroom token optimization proxy";

    package = lib.mkOption {
      type = lib.types.package;
      default = defaultPackage;
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/headroom-ai.nix { }";
      description = "Headroom package to install and run.";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address for the Headroom proxy to bind.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      default = 8787;
      description = "Port for the Headroom proxy to bind.";
    };

    mode = lib.mkOption {
      type = lib.types.enum [
        "token"
        "cache"
      ];
      default = "token";
      description = "Headroom optimization mode.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "%h/.headroom";
      description = "State directory used for Headroom logs and runtime data.";
    };

    environment = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "Extra environment variables for the Headroom proxy service.";
    };

    extraArgs = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Additional arguments appended to `headroom proxy`.";
    };

    agents = {
      opencode = lib.mkEnableOption ''
        routing OpenCode's LLM Platform provider traffic through the Headroom
        proxy. Requires both `local.headroom.enable` and
        `local.opencode.llmPlatform.enable`.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    systemd.user.services.headroom-proxy = {
      Unit = {
        Description = "Headroom AI proxy";
        Documentation = [ "https://github.com/headroomlabs-ai/headroom" ];
      };

      Service = {
        Type = "simple";
        WorkingDirectory = config.home.homeDirectory;
        Environment = lib.mapAttrsToList (name: value: "${name}=${value}") (
          defaultEnvironment // cfg.environment
        );
        ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p ${logDir}";
        ExecStart = lib.escapeShellArgs ([ "${cfg.package}/bin/headroom" ] ++ proxyArgs);
        Restart = "on-failure";
        RestartSec = "5s";
      };

      Install.WantedBy = [ "default.target" ];
    };
  };
}
