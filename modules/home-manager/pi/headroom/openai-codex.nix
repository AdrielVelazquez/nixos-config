{
  config,
  lib,
  piLib,
  ...
}:
let
  cfg = config.local.headroom.pi;
  urlEnv = "HEADROOM_PI_CODEX_PROXY_URL";
  requiredEnv = "HEADROOM_PI_CODEX_PROXY_REQUIRED";
  entry = piLib.mkEntry {
    name = "pi-headroom-codex.ts";
    module = "headroom-codex";
    factory = "routeCodexThroughHeadroom";
    args = { inherit urlEnv requiredEnv; };
  };
in
{
  options.local.headroom.pi.providers.openai-codex.enable =
    lib.mkEnableOption "Headroom routing for Pi's OpenAI Codex subscription provider";
  config = lib.mkIf (config.local.pi.enable && cfg.enable && cfg.providers.openai-codex.enable) {
    local.headroom.pi.adapters.openai-codex = {
      inherit urlEnv requiredEnv;
      upstreamOrigins = [ "https://chatgpt.com" ];
    };
    local.pi.extraSettings.extensions = [ "${entry}" ];
    local.pi.requiredChildExtensions = [
      {
        id = "headroom-codex";
        path = "${entry}";
      }
    ];
  };
}
