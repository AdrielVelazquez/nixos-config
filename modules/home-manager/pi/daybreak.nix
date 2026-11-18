{
  config,
  lib,
  piLib,
  ...
}:
let
  cfg = config.local.pi.daybreak;
  entry = piLib.mkReexport {
    name = "pi-openai-daybreak-blue.ts";
    module = "openai-daybreak-blue";
  };
in
{
  options.local.pi.daybreak = {
    enable = lib.mkEnableOption "the Daybreak Blue alias on ChatGPT sign-in";
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { daybreak = "${entry}"; });
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    local.pi.extraSettings.extensions = [ cfg.entries.daybreak ];
  };
}
