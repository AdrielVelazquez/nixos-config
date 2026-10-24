{
  lib,
  config,
  ...
}:

let
  cfg = config.local.opencode.go;
in
{
  options.local.opencode.go = {
    enable = lib.mkEnableOption "the OpenCode Go subscription provider";

    defaultModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "opencode-go/kimi-k2.7-code";
      description = ''
        Default OpenCode model when the OpenCode Go provider is enabled. Connect the
        console account once with `/connect`; no key is managed here.
      '';
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings =
      lib.optionalAttrs (cfg.defaultModel != null) {
        model = cfg.defaultModel;
      }
      // lib.optionalAttrs config.local.headroom.enable {
        # Only OpenAI-compatible Go models are routed; Anthropic, Responses and
        # Gemini models stay on their direct gateway paths.
        plugins = [
          {
            package = "file://${../../dotfiles/opencode/plugins/headroom-go}";
            options = {
              proxyURL = "http://127.0.0.1:${toString config.local.headroom.wrapDefaults.port}";
              upstreamBaseURL = "https://opencode.ai/inference/go/openai/v1";
            };
          }
        ];
      };
    # Explicit allowlist: the proxy's DNS-based SSRF check rejected opencode.ai
    # in a long-lived proxy and fell back to api.openai.com with the Go key.
    local.headroom.proxyEnv = lib.mkIf config.local.headroom.enable {
      HEADROOM_ALLOWED_BASE_URLS = lib.mkDefault "https://opencode.ai";
    };
  };
}
