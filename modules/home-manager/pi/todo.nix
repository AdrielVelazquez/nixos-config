{
  config,
  lib,
  piLib,
  ...
}:
let
  cfg = config.local.pi.todo;
  entry = piLib.mkReexport {
    name = "pi-todo.ts";
    module = "todo";
  };
in
{
  options.local.pi.todo = {
    enable = piLib.mkFeatureEnable "the `todo` task-list tool for the interactive session";
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { todo = "${entry}"; });
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # Interactive session only: children are given explicit tool lists and keep to their delegated task.
    local.pi.extraSettings.extensions = [ cfg.entries.todo ];
  };
}
