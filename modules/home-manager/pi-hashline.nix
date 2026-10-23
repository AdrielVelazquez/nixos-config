{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.hashline;
in
{
  options.local.pi.hashline = {
    enable = lib.mkEnableOption "hash-anchored read, edit and grep for Pi" // {
      default = true;
      example = false;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/pi-hashline.nix { };
    };
    entry = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      internal = true;
      default = "${cfg.package}/${cfg.package.packageRoot}/index.ts";
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # The package overrides Pi's `read` and `edit` and adds `grep`. The interactive session loads it as a
    # plain extension; only the file-writing children (build, plan) load it too, so read-only scouts and
    # explorers keep Pi's native, anchor-free output.
    local.pi.extraSettings.extensions = [ cfg.entry ];
    local.pi.routing.writerExtensions = [ cfg.entry ];
  };
}
