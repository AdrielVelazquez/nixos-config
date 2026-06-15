{
  lib,
  config,
  inputs,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode;
  headroomCfg = config.local.headroom;
  headroomEnabled = headroomCfg.enable && (headroomCfg.agents.opencode or false);
  githubTokenSecretName = "codex_github_token";
  githubTokenEnvVar = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN";
  jsonFormat = pkgs.formats.json { };
  baseConfig = builtins.fromJSON (builtins.readFile ../../dotfiles/opencode/opencode.json);
  headroomProvider = lib.optionalAttrs headroomEnabled {
    provider = {
      headroom = {
        name = "Headroom proxy";
        npm = "@ai-sdk/openai-compatible";
        options = {
          baseURL = headroomCfg.proxyBaseUrl;
          apiKey = "{env:OPENAI_API_KEY}";
        };
        models = {
          "gpt-5.2" = {
            name = "GPT-5.2 via Headroom";
          };
        };
      };
    };
  };
  settings = lib.recursiveUpdate (
    baseConfig
    // {
      plugin = lib.unique ((baseConfig.plugin or [ ]) ++ [ "${inputs.superpowers}" ]);
    }
  ) headroomProvider;

  opencodeWithGithubToken = pkgs.writeShellScriptBin "opencode" ''
    if [ -z "''${${githubTokenEnvVar}:-}" ] && [ -r "${
      config.sops.secrets.${githubTokenSecretName}.path
    }" ]; then
      export ${githubTokenEnvVar}="$(${pkgs.coreutils}/bin/cat "${
        config.sops.secrets.${githubTokenSecretName}.path
      }")"
    fi

    if ${lib.boolToString headroomEnabled}; then
      exec ${headroomCfg.sessionHelper}/bin/headroom-agent-session opencode -- ${pkgs.opencode}/bin/opencode "$@"
    fi

    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  options.local.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI";
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
