# modules/home-manager/opencode-hashline.nix
#
# Hash-anchored read and edit for OpenCode: the pinned opencode-v2-hashline plugin (packages/opencode-v2-hashline.nix),
# which overrides `read` and adds replace, replace_match, insert, copy, move, anchor_grep and undo_last_change. The
# repo's guard plugin (dotfiles/opencode/plugins/hashline-guard) checks those tools against the read and edit rules in
# opencode.json, because the hashline reads do not consult them, and refuses OpenCode's built-in edit and apply_patch.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.local.opencode.hashline;
in
{
  options.local.opencode.hashline = {
    enable =
      lib.mkEnableOption "hash-anchored read and edit for OpenCode, with the repo's permission guard"
      // {
        default = true;
        example = false;
      };
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.callPackage ../../packages/opencode-v2-hashline.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage ../../packages/opencode-v2-hashline.nix { }";
    };
  };

  config = lib.mkIf (config.local.opencode.enable && cfg.enable) {
    local.opencode.extraSettings.plugins = [
      { package = "file://${cfg.package}"; }
      { package = "file://${../../dotfiles/opencode/plugins/hashline-guard}"; }
    ];
  };
}
