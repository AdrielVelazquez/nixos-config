# modules/home-manager/opencode-rtk.nix
#
# OpenCode's counterpart to Pi's rtk extension (modules/home-manager/pi/rtk.nix): every shell command is rewritten
# through `rtk rewrite` before it runs, so tool output reaches the model compacted. The rewrite logic stays in rtk.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.rtk;
in
{
  options.local.opencode.rtk = {
    enable = lib.mkEnableOption "rewriting OpenCode shell commands through rtk before they run" // {
      default = true;
      example = false;
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rtk;
      defaultText = lib.literalExpression "pkgs.rtk";
      description = "The rtk build whose `rtk rewrite` the plugin delegates to.";
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings.plugins = [
      {
        package = "file://${../../dotfiles/opencode/plugins/rtk}";
        options.bin = lib.getExe cfg.package;
      }
    ];
  };
}
