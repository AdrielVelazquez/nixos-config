{
  lib,
  config,
  ...
}:

let
  cfg = config.local.opencode.llmPlatform;
  headroomCfg = config.local.headroom;
  llmPlatformPlugin = "@reddit/opencode-llm-platform@https://artifactory.build.ue1.snooguts.net:443/artifactory/api/npm/reddit-npm-prod/%40reddit/opencode-llm-platform/-/opencode-llm-platform-0.0.2.tgz";

  # Route inference through Headroom while leaving plugin model discovery on
  # the real endpoint. Headroom reconstructs and then strips these headers.
  routeThroughHeadroom = cfg.enable && headroomCfg.enable && headroomCfg.agents.opencode;
  upstreamParts = lib.splitString "/" cfg.upstreamBaseUrl;
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

  llmPlatformSettings = lib.optionalAttrs cfg.enable (
    {
      share = "disabled";
      plugin = [ cfg.plugin ];
    }
    // lib.optionalAttrs (cfg.defaultModel != null) {
      model = cfg.defaultModel;
    }
  );
in
{
  options = {
    local.opencode.llmPlatform = {
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

    local.headroom.agents.opencode = lib.mkEnableOption ''
      routing OpenCode's LLM Platform provider traffic through the Headroom
      proxy. Requires both `local.headroom.enable` and
      `local.opencode.llmPlatform.enable`.
    '';
  };

  config = lib.mkIf config.local.opencode.enable {
    assertions = [
      {
        assertion = headroomCfg.agents.opencode -> (cfg.enable && headroomCfg.enable);
        message = ''
          local.headroom.agents.opencode requires both
          local.opencode.llmPlatform.enable and local.headroom.enable.
        '';
      }
    ];

    local.opencode.extraSettings = lib.recursiveUpdate llmPlatformSettings headroomProviderSettings;
  };
}
