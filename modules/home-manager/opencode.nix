{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode;
  # Reuse the existing encrypted GitHub credential; its value is read only at runtime.
  githubTokenSecretName = "codex_github_token";
  githubTokenEnvVar = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN";
  jsonFormat = pkgs.formats.json { };
  opencodePackage = pkgs.opencode;
  baseConfig = builtins.fromJSON (builtins.readFile ../../dotfiles/opencode/opencode.json);
  extendedSettings = lib.recursiveUpdate baseConfig (
    builtins.removeAttrs cfg.extraSettings [
      "plugins"
      "instructions"
    ]
  );

  settings = extendedSettings // {
    plugins = lib.unique (
      (baseConfig.plugins or [ ])
      ++ (cfg.extraSettings.plugins or [ ])
      ++ [ { package = "file://${inputs.superpowers}"; } ]
    );
    instructions = lib.unique (
      (baseConfig.instructions or [ ]) ++ (cfg.extraSettings.instructions or [ ])
    );
  };

  opencodeWithGithubToken =
    (pkgs.writeShellScriptBin "opencode" ''
      if [ -z "''${${githubTokenEnvVar}:-}" ] && [ -r "${
        config.sops.secrets.${githubTokenSecretName}.path
      }" ]; then
        export ${githubTokenEnvVar}="$(${pkgs.coreutils}/bin/cat "${
          config.sops.secrets.${githubTokenSecretName}.path
        }")"
      fi

      ${lib.optionalString config.local.headroom.enable ''
        if [ "''${HEADROOM_OPENCODE_WRAPPED:-0}" != 1 ]; then
          case "''${1:-}" in
            upgrade|update|uninstall|api|debug|auth|mcp|plugin|models|stats|session|service|pair|serve|acp|--help|-h|--version|-v|--completions)
              ;;
            *)
              exec ${lib.getExe config.local.headroom.package} wrap opencode -- "$@"
              ;;
          esac
        fi
      ''}
      unset HEADROOM_OPENCODE_WRAPPED HEADROOM_OPENCODE_REAL_BIN
      exec ${lib.getExe opencodePackage} "$@"
    '').overrideAttrs
      (previous: {
        pname = "opencode";
        version = opencodePackage.version;
        passthru = (previous.passthru or { }) // {
          unwrapped = opencodePackage;
          # Home Manager's programs.opencode.validateFiles.config reads passthru.jsonschema.config.
          jsonschema = opencodePackage.passthru.jsonschema;
        };
      });
in
{
  options.local.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI";

    extraSettings = lib.mkOption {
      type = jsonFormat.type;
      default = { };
      description = "Additional OpenCode JSON settings merged over the repository base configuration.";
    };

    cliSettings = lib.mkOption {
      type = jsonFormat.type;
      default = {
        diffs.wrap = "word";
        session = {
          sidebar = "hide";
          scrollbar = false;
          thinking = "show";
          image_preview = true;
          permissions = "autoaccept";
        };
        animations = true;
        leader.timeout = 7500;
        attention.notifications = true;
        tabs.layout = "vertical";
        debug.devtools = true;
      };
      description = "OpenCode terminal settings written to ~/.config/opencode/cli.json.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.${githubTokenSecretName} = { };

    programs.opencode = {
      enable = true;
      package = lib.hiPrio opencodeWithGithubToken;
      inherit settings;
      skills = {
        ce-compound = "${inputs.compound-engineering}/skills/ce-compound";
        ce-compound-refresh = "${inputs.compound-engineering}/skills/ce-compound-refresh";
      };
      context = builtins.readFile ../../dotfiles/opencode/AGENTS.md;
      # Home Manager's MCP adapter emits the v1 schema. V2 uses settings.mcp.servers.
      enableMcpIntegration = false;
      validateFiles.config = true;
    };
    xdg.configFile."opencode/opencode.json".force = true;
    xdg.configFile."opencode/cli.json" = {
      source = jsonFormat.generate "opencode-cli.json" (
        { "$schema" = "https://opencode.ai/v2/cli.json"; } // cfg.cliSettings
      );
      force = true;
    };
  };
}
