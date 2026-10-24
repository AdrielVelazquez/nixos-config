{
  config,
  lib,
  piLib,
  ...
}:
let
  cfg = config.local.headroom.pi;
  urlEnv = "HEADROOM_PI_PROVIDERS_PROXY_URL";
  requiredEnv = "HEADROOM_PI_PROVIDERS_PROXY_REQUIRED";
  originOf = url: builtins.head (builtins.match "(https://[^/]+)(/.*)?" url);
  entry = piLib.mkEntry {
    name = "pi-headroom-providers.ts";
    module = "headroom-providers";
    factory = "routeProvidersThroughHeadroom";
    args = {
      routes = cfg.providers;
      inherit urlEnv requiredEnv;
    };
  };
in
{
  options.local.headroom.pi.providers = lib.mkOption {
    type = lib.types.attrsOf (lib.types.strMatching "https://[a-zA-Z0-9.-]+(:[0-9]+)?(/[^?# ]*)?/v1");
    default = { };
    example = {
      opencode-go = "https://opencode.ai/inference/go/v1";
    };
    description = ''
      Pi's built-in providers whose inference is routed through the session's Headroom proxy, mapped to
      their OpenAI-compatible upstream base URL (ending in /v1, as in Pi's provider catalog). This is the
      adapter for providers that have no extension of their own; LLM Platform keeps its own through
      `local.pi.llmPlatform`. Only the chat-completions and responses paths of those providers are routed.
    '';
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable && cfg.providers != { }) {
    local.headroom.pi.adapters.pi-providers = {
      inherit urlEnv requiredEnv;
      upstreamOrigins = lib.unique (map originOf (lib.attrValues cfg.providers));
    };
    local.pi.extraSettings.extensions = [ "${entry}" ];
    local.pi.requiredChildExtensions = [
      {
        id = "headroom-providers";
        path = "${entry}";
      }
    ];
  };
}
