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
  opencodePackage = inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default.override {
    # Preserve upstream's hashed node_modules; bundle with current Bun to avoid
    # the older runtime's plugin entrypoint-resolution bug. See TODO.md.
    bun = pkgs.bun;
  };
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
      context = ''
        # Workflow and project learnings

        Use Superpowers for the development workflow. The installed CE skills
        supplement it with durable project learnings.

        Before related work, consult relevant existing notes in the repository's
        docs/solutions directory. If .compound-engineering/config.yaml defines
        docs_root, use that repository-relative root's solutions directory instead,
        following the CE skill's path validation. Read only task-relevant notes.

        After meaningful, verified work and before the final handoff, invoke
        ce-compound with mode:non-interactive depth:lightweight. Capture reusable
        findings whose reasoning is not already clear from the code, tests, or
        existing documentation. Routine changes may produce no learning document.
        Keep the notes in the repository's learning directory, never the installed
        skill source. Do not record secrets or unrelated personal information.

        Use ce-compound-refresh when the user requests a learning review or when
        relevant notes are stale or contradictory; scope it to those notes instead
        of auditing the whole collection after every task.

        Explicit user requests and repository instructions take precedence,
        including approval requirements and Git commit boundaries.
      '';
      # Home Manager's MCP adapter emits the v1 schema. V2 uses settings.mcp.servers.
      enableMcpIntegration = false;
    };
    xdg.configFile."opencode/opencode.json".force = true;
  };
}
