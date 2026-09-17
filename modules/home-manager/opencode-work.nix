{
  lib,
  config,
  ...
}:

let
  cfg = config.local.opencode.llmPlatform;
  headroomEnabled = config.local.headroom.enable;
  proxyURL = "http://127.0.0.1:${toString config.local.headroom.wrapDefaults.port}";
  upstreamOrigin = builtins.head (builtins.match "(https?://[^/]+)(/.*)?" cfg.baseURL);
  llmPlatformPlugin = "@reddit/opencode-llm-platform-v2@https://artifactory.build.ue1.snooguts.net:443/artifactory/api/npm/reddit-npm-prod/%40reddit/opencode-llm-platform-v2/-/opencode-llm-platform-v2-0.1.1.tgz";

  llmPlatformSettings = lib.optionalAttrs cfg.enable (
    {
      share = "disabled";
      plugins = [
        {
          package = cfg.plugin;
          options.baseURL = cfg.baseURL;
        }
      ]
      ++ lib.optionals headroomEnabled [
        {
          package = "file://${../../dotfiles/opencode/plugins/headroom}";
          options = {
            inherit proxyURL;
            upstreamBaseURL = cfg.baseURL;
          };
        }
      ];
    }
    // lib.optionalAttrs headroomEnabled {
      # Keep inference on loopback even if the transport plugin fails to load.
      providers.llmplatform = {
        settings.baseURL = "${proxyURL}/v1";
        headers."x-headroom-base-url" = upstreamOrigin;
        transport = "http";
      };
      mcp.servers.headroom = {
        type = "local";
        command = [
          "headroom"
          "mcp"
          "serve"
        ];
        environment.HEADROOM_PROXY_URL = proxyURL;
      };
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

    baseURL = lib.mkOption {
      type = lib.types.strMatching "https?://[a-zA-Z0-9.-]+(:[0-9]+)?(/[^?#]*)?";
      default = "https://llm-platform.pri.serving-iad-a01.aws.achilles.snooguts.net/v1/openai";
      description = "LLM Platform gateway for model discovery and Headroom forwarding. Credentials remain runtime-only.";
    };
    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "llmplatform/claude-opus-4-8";
      description = "Default OpenCode model when the LLM Platform plugin is enabled.";
    };
  };

  config = lib.mkIf config.local.opencode.enable {
    local.opencode.extraSettings = llmPlatformSettings;
    local.headroom.proxyEnv = lib.mkIf (cfg.enable && headroomEnabled) {
      HEADROOM_ALLOWED_BASE_URLS = lib.mkDefault upstreamOrigin;
    };
  };
}
