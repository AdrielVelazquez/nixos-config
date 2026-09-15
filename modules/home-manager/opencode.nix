{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode;
  githubTokenSecretName = "codex_github_token";
  githubTokenEnvVar = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN";
  jsonFormat = pkgs.formats.json { };
  opencodePackage = pkgs.callPackage "${inputs.opencode-nix}/nix/opencode.nix" {
    inherit (inputs.opencode.packages.${pkgs.stdenv.hostPlatform.system}.default) node_modules;
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
    # Superpowers still uses v1 plugin hooks. Native instructions retain its
    # bootstrap while ai-cli-skills installs the complete skill directories.
    instructions = lib.unique (
      (baseConfig.instructions or [ ])
      ++ (cfg.extraSettings.instructions or [ ])
      ++ [ "${inputs.superpowers}/skills/using-superpowers/SKILL.md" ]
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

    home.packages = [ (lib.hiPrio opencodeWithGithubToken) ];

    home.file.".config/opencode/opencode.json" = {
      source = jsonFormat.generate "opencode.json" settings;
      force = true;
    };

    local.ai-cli-skills = {
      enable = true;
      targets.opencode = true;
    };
  };
}
