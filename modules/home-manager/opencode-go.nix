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
    local.opencode.extraSettings = lib.optionalAttrs (cfg.defaultModel != null) {
      model = cfg.defaultModel;
    };
  };
}
