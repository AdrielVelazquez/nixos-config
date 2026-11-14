{
  config,
  lib,
  piLib,
  ...
}:
let
  cfg = config.local.pi.goUsage;
  keySecret = config.local.pi.apiKeys."opencode-go" or null;
  # The generated entry carries the secret's runtime path, never its value.
  keyFile = if keySecret == null then "" else config.sops.secrets.${keySecret}.path;
  entry = piLib.mkEntry {
    name = "pi-opencode-go-usage.ts";
    module = "opencode-go-usage";
    factory = "createOpenCodeGoUsage";
    args = {
      inherit keyFile;
      inherit (cfg) minRefreshMs;
    };
  };
in
{
  options.local.pi.goUsage = {
    enable = lib.mkEnableOption "OpenCode Go monthly usage in Pi's footer" // {
      default = keySecret != null;
      defaultText = lib.literalExpression ''config.local.pi.apiKeys ? "opencode-go"'';
    };
    minRefreshMs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 60000;
      description = "Minimum time between usage requests; the footer refreshes at session start and after each turn.";
    };
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { usage = "${entry}"; });
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    assertions = [
      {
        assertion = keySecret != null;
        message = "local.pi.goUsage needs local.pi.apiKeys.opencode-go because the usage endpoint requires its API key";
      }
    ];
    local.pi.extraSettings.extensions = [ cfg.entries.usage ];
  };
}
