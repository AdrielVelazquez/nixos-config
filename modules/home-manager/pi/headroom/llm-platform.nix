{ config, lib, ... }:
let
  cfg = config.local.headroom.pi;
  provider = config.local.pi.llmPlatform;
in
{
  options.local.headroom.pi.providers.llm-platform.enable =
    lib.mkEnableOption "Headroom routing for Pi's LLM Platform provider";
  config =
    lib.mkIf
      (config.local.pi.enable && cfg.enable && cfg.providers.llm-platform.enable && provider.enable)
      {
        local.headroom.pi.adapters.llm-platform = {
          urlEnv = "LLM_PLATFORM_INFERENCE_PROXY_URL";
          requiredEnv = "LLM_PLATFORM_INFERENCE_PROXY_REQUIRED";
          upstreamOrigins = [ provider.upstreamOrigin ];
        };
      };
}
