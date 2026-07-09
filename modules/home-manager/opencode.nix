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
  githubTokenSecretName = "codex_github_token";
  githubTokenEnvVar = "CODEX_GITHUB_PERSONAL_ACCESS_TOKEN";
  jsonFormat = pkgs.formats.json { };
  baseConfig = builtins.fromJSON (builtins.readFile ../../dotfiles/opencode/opencode.json);
  llmPlatformPlugin = "@reddit/opencode-llm-platform@https://artifactory.build.ue1.snooguts.net:443/artifactory/api/npm/reddit-npm-prod/%40reddit/opencode-llm-platform/-/opencode-llm-platform-0.0.2.tgz";
  llmPlatformSettings = lib.optionalAttrs cfg.llmPlatform.enable (
    {
      share = "disabled";
    }
    // lib.optionalAttrs (cfg.llmPlatform.defaultModel != null) {
      model = cfg.llmPlatform.defaultModel;
    }
  );

  # Route the LLM Platform providers through the Headroom proxy without the
  # bundled OpenCode transport plugin (the pip wheel is pip-only and ships no
  # `entry.opencode.js`). Instead we replicate that plugin's header contract:
  # point each provider's baseURL at the proxy's dedicated `/v1` route and pass
  # `x-headroom-base-url` (upstream origin) + `x-headroom-original-path` (the
  # real upstream path, including the mandatory `/openai` segment). Headroom
  # >= 0.29.0 reconstructs `<origin><original-path>` and strips both headers
  # before forwarding upstream. The plugin still discovers models directly from
  # the real endpoint at startup; only inference calls traverse the proxy.
  routeThroughHeadroom =
    cfg.llmPlatform.enable && headroomCfg.enable && headroomCfg.agents.opencode;

  upstreamParts = lib.splitString "/" cfg.llmPlatform.upstreamBaseUrl;
  upstreamOrigin = lib.concatStringsSep "/" (lib.take 3 upstreamParts);
  upstreamPathPrefix = "/" + lib.concatStringsSep "/" (lib.drop 3 upstreamParts);
  proxyBaseUrl = "http://${headroomCfg.host}:${toString headroomCfg.port}/v1";

  headroomProviderOptions = originalPath: {
    options = {
      baseURL = proxyBaseUrl;
      headers = {
        "x-headroom-base-url" = upstreamOrigin;
        "x-headroom-original-path" = originalPath;
      };
    };
  };

  headroomProviderSettings = lib.optionalAttrs routeThroughHeadroom {
    provider = {
      llmplatform = headroomProviderOptions "${upstreamPathPrefix}/chat/completions";
      llmplatform-gpt = headroomProviderOptions "${upstreamPathPrefix}/responses";
    };
  };

  settings = lib.recursiveUpdate (
    baseConfig
    // llmPlatformSettings
    // {
      plugin = lib.unique (
        (baseConfig.plugin or [ ])
        ++ lib.optionals cfg.llmPlatform.enable [ cfg.llmPlatform.plugin ]
        ++ [ "${inputs.superpowers}" ]
      );
    }
  ) headroomProviderSettings;

  opencodeWithGithubToken = pkgs.writeShellScriptBin "opencode" ''
    if [ -z "''${${githubTokenEnvVar}:-}" ] && [ -r "${
      config.sops.secrets.${githubTokenSecretName}.path
    }" ]; then
      export ${githubTokenEnvVar}="$(${pkgs.coreutils}/bin/cat "${
        config.sops.secrets.${githubTokenSecretName}.path
      }")"
    fi

    exec ${pkgs.opencode}/bin/opencode "$@"
  '';
in
{
  options.local.opencode = {
    enable = lib.mkEnableOption "OpenCode CLI";

    llmPlatform = {
      enable = lib.mkEnableOption "Reddit LLM Platform OpenCode plugin";

      plugin = lib.mkOption {
        type = lib.types.str;
        default = llmPlatformPlugin;
        description = "OpenCode plugin spec for Reddit's LLM Platform provider.";
      };

      defaultModel = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "llmplatform/claude-opus-4-8";
        description = "Default OpenCode model when the LLM Platform plugin is enabled.";
      };

      upstreamBaseUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://llm-platform.pri.serving-iad-a01.aws.achilles.snooguts.net/v1/openai";
        description = ''
          The real LLM Platform OpenAI-compatible base URL. Used only when
          routing through Headroom (`local.headroom.agents.opencode`): the
          origin becomes `x-headroom-base-url` and the path prefix (e.g.
          `/v1/openai`) is preserved via `x-headroom-original-path` so the
          proxy forwards to the correct upstream route.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion =
          headroomCfg.agents.opencode -> (cfg.llmPlatform.enable && headroomCfg.enable);
        message = ''
          local.headroom.agents.opencode requires both
          local.opencode.llmPlatform.enable and local.headroom.enable.
        '';
      }
    ];

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
