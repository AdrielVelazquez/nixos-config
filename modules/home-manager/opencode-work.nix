{
  lib,
  config,
  ...
}:

let
  cfg = config.local.opencode.llmPlatform;
  llmPlatformPlugin = "@reddit/opencode-llm-platform@https://artifactory.build.ue1.snooguts.net:443/artifactory/api/npm/reddit-npm-prod/%40reddit/opencode-llm-platform/-/opencode-llm-platform-0.0.2.tgz";

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
  options.local.opencode.llmPlatform = {
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
  };

  config = lib.mkIf config.local.opencode.enable {
    local.opencode.extraSettings = llmPlatformSettings;
  };
}
