{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode;
  skillRoot = "${inputs.compound-engineering}/skills";
  skillNames = lib.filter (name: builtins.pathExists "${skillRoot}/${name}/SKILL.md") (
    lib.attrNames (builtins.readDir skillRoot)
  );
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
    plugins = lib.unique ((baseConfig.plugins or [ ]) ++ (cfg.extraSettings.plugins or [ ]));
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
      skills = lib.genAttrs skillNames (name: "${skillRoot}/${name}");
      # Home Manager's MCP adapter emits the v1 schema. V2 uses settings.mcp.servers.
      enableMcpIntegration = false;
    };
    xdg.configFile."opencode/opencode.json".force = true;
  };
}
