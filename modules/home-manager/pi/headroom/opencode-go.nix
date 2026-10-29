{ config, lib, ... }:
let
  cfg = config.local.headroom.pi;
in
{
  options.local.headroom.pi.providers.opencode-go.enable =
    lib.mkEnableOption "Headroom routing for Pi's OpenCode Go provider";
  config = lib.mkIf (config.local.pi.enable && cfg.enable && cfg.providers.opencode-go.enable) {
    local.headroom.pi.routes.opencode-go = "https://opencode.ai/inference/go/v1";
  };
}
