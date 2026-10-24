{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.local.pi.todo;
  entry = pkgs.writeText "pi-todo.ts" ''
    export { default } from "${../../dotfiles/pi/extensions}/todo.ts";
  '';
in
{
  options.local.pi.todo = {
    enable = lib.mkEnableOption "the `todo` task-list tool for the interactive session" // {
      default = true;
      example = false;
    };
    entries = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      readOnly = true;
      internal = true;
      default = lib.optionalAttrs cfg.enable { todo = "${entry}"; };
    };
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # Interactive session only: children are given explicit tool lists and keep to their delegated task.
    local.pi.extraSettings.extensions = [ cfg.entries.todo ];
  };
}
