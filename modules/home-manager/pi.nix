{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi;
  json = pkgs.formats.json { };
  settings = lib.recursiveUpdate {
    enableInstallTelemetry = false;
    enableAnalytics = false;
    hideThinkingBlock = false;
    fullscreenScrollbar = "hidden";
    terminal.showImages = true;
  } (builtins.removeAttrs cfg.extraSettings [ "extensions" ]);
  package =
    (pkgs.writeShellScriptBin "pi" ''
      if [ -z "''${PI_CODING_AGENT_DIR:-}" ]; then
        PI_CODING_AGENT_DIR=${lib.escapeShellArg cfg.agentDir}
      fi
      export PI_CODING_AGENT_DIR
      # Read the existing SOPS credential only in the running user's process.
      # The derivation contains its runtime path, never the decrypted value.
      if [ -z "''${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN:-}" ] && [ -r ${lib.escapeShellArg config.sops.secrets.codex_github_token.path} ]; then
        export CODEX_GITHUB_PERSONAL_ACCESS_TOKEN="$(${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.sops.secrets.codex_github_token.path})"
      fi
      exec ${lib.getExe (if cfg.launcher == null then cfg.package else cfg.launcher)} "$@"
    '').overrideAttrs
      (previous: {
        pname = "pi-coding-agent";
        version = cfg.package.version or "unknown";
        passthru = (previous.passthru or { }) // {
          unwrapped = cfg.package;
        };
      });
in
{
  options.local.pi = {
    enable = lib.mkEnableOption "Pi coding agent";
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.pi-coding-agent;
      description = "Unwrapped Pi package; integrations supply an optional launcher separately.";
    };
    launcher = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Optional integration launcher around the unwrapped Pi package.";
    };
    agentDir = lib.mkOption {
      type = lib.types.str;
      default = "${config.home.homeDirectory}/.pi/agent";
      description = "Stable Pi configuration and private runtime-state directory.";
    };
    extraSettings = lib.mkOption {
      type = json.type;
      default = { };
      description = "Additional native Pi settings; extensions are combined with the base question tool.";
    };
    mcpServers = lib.mkOption {
      type = json.type;
      default = { };
      description = "Native Pi MCP declarations; credentials must use runtime environment substitution.";
    };
    requiredChildExtensions = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            id = lib.mkOption { type = lib.types.str; };
            path = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      default = [ ];
      description = "Trusted extension entry points required in every native child session.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.codex_github_token = { };
    programs.pi-coding-agent = {
      enable = true;
      inherit package;
      configDir = cfg.agentDir;
      settings = settings // {
        extensions = lib.unique (
          [ "${../../dotfiles/pi/extensions/question.ts}" ] ++ (cfg.extraSettings.extensions or [ ])
        );
      };
    };
    home.file."${cfg.agentDir}/mcp.json".source = json.generate "pi-mcp.json" {
      mcpServers = lib.recursiveUpdate {
        github = {
          url = "https://api.githubcopilot.com/mcp/";
          headers.Authorization = "Bearer \${CODEX_GITHUB_PERSONAL_ACCESS_TOKEN}";
        };
      } cfg.mcpServers;
    };
  };
}
