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
      routes = cfg.routes;
      inherit urlEnv requiredEnv;
    };
  };
in
{
  imports = [ ./headroom ];

  options.local.headroom.pi.routes = lib.mkOption {
    type = lib.types.attrsOf (lib.types.strMatching "https://[a-zA-Z0-9.-]+(:[0-9]+)?(/[^?# ]*)?/v1");
    default = { };
    internal = true;
    description = "OpenAI-compatible provider routes contributed by enabled Headroom provider modules.";
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable && cfg.routes != { }) {
    local.headroom.pi.adapters.pi-providers = {
      inherit urlEnv requiredEnv;
      upstreamOrigins = lib.unique (map originOf (lib.attrValues cfg.routes));
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
