{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi;
  json = pkgs.formats.json { };
  settingsTarget = "${cfg.agentDir}/settings.json";
  opencodeSkin = config.local.pi.ui.enable && config.local.pi.ui.style == "opencode";
  installSettings = pkgs.callPackage ../../../packages/pi-install-settings.nix { };
  # Pi runs this when it needs the key and trims stdout, so the secret is read at run time, never at evaluation.
  apiKeyCommand =
    name: "!${pkgs.coreutils}/bin/cat ${lib.escapeShellArg config.sops.secrets.${name}.path}";
  settings = lib.recursiveUpdate (
    {
      enableInstallTelemetry = false;
      enableAnalytics = false;
      hideThinkingBlock = false;
      fullscreenScrollbar = "hidden";
      terminal.showImages = true;
    }
    # Pi records the changelog it showed in settings.json. Declaring the pinned version
    # keeps ordinary sessions from rewriting the file, so a switch only reports real changes.
    // lib.optionalAttrs (cfg.package ? version) { lastChangelogVersion = cfg.package.version; }
  ) (builtins.removeAttrs cfg.extraSettings [ "extensions" ]);
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
    discoveryTools.enable =
      lib.mkEnableOption "Pi's native read-only `find` and `ls` tools in the interactive session"
      // {
        default = true;
        example = false;
      };
    apiKeys = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        opencode-go = "opencode_api_key";
      };
      description = ''
        Pi provider IDs whose API key comes from a SOPS secret, mapped to the secret's name. Nix writes a
        read-only `models.json` whose `apiKey` is a command that reads the secret's runtime path, so the key
        never enters the Nix store or Pi's environment. A key stored by `/login` still takes precedence, and the
        provider's environment variable remains the fallback. The secret must exist in the SOPS file before this
        is set, or sops-nix fails to install every secret.
      '';
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
    # Pi starts with read, bash, edit and write only. `find` respects .gitignore and runs the `fd` from Pi's wrapper.
    local.pi.extraSettings.defaultTools = lib.mkIf cfg.discoveryTools.enable [
      "+find"
      "+ls"
    ];
    sops.secrets = {
      codex_github_token = { };
    }
    // lib.mapAttrs' (_: name: lib.nameValuePair name { }) cfg.apiKeys;
    programs.pi-coding-agent = {
      enable = true;
      inherit package;
      configDir = cfg.agentDir;
      settings = settings // {
        extensions = lib.unique (
          [ "${../../../dotfiles/pi/extensions/question.ts}" ]
          # The opencode skin ends each answer with its own model/duration footer, including model switches.
          ++ lib.optional (!opencodeSkin) "${../../../dotfiles/pi/extensions/model-hint.ts}"
          ++ (cfg.extraSettings.extensions or [ ])
        );
      };
    };
    # Pi and its extensions persist choices into settings.json at runtime (/lsp, the subagent
    # watchdog, theme and model choices). A store symlink makes each of those fail with EACCES,
    # so the generated file is installed as a writable copy and reset on every switch.
    home.file.${settingsTarget}.enable = lib.mkForce false;
    home.activation.piSettings = lib.hm.dag.entryAfter [ "linkGeneration" ] ''
      run ${lib.getExe installSettings} ${
        config.home.file.${settingsTarget}.source
      } ${lib.escapeShellArg settingsTarget}
    '';
    home.file."${cfg.agentDir}/models.json" = lib.mkIf (cfg.apiKeys != { }) {
      source = json.generate "pi-models.json" {
        providers = lib.mapAttrs (_: name: { apiKey = apiKeyCommand name; }) cfg.apiKeys;
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
