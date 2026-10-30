{
  config,
  lib,
  piLib,
  ...
}:
let
  cfg = config.local.pi.todo;
  entry = piLib.mkEntry {
    name = "pi-todo.ts";
    module = "todo";
    factory = "createTodo";
    args = {
      inherit (cfg)
        maxWidgetLines
        collapseKey
        locale
        hideCompleted
        ;
    };
  };
in
{
  options.local.pi.todo = {
    enable = piLib.mkFeatureEnable "the `todo` task-list tool for the interactive session";
    maxWidgetLines = lib.mkOption {
      type = lib.types.ints.between 3 101;
      default = 8;
      description = "Compact widget content rows, heading included; native tool expansion shows every task.";
    };
    collapseKey = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "ctrl+shift+t";
      description = "Pi shortcut for collapsing the task widget; null registers no shortcut.";
    };
    locale = lib.mkOption {
      type = lib.types.enum [
        "en"
        "de"
        "es"
        "fr"
        "pt"
        "pt-BR"
        "ru"
        "uk"
        "zh"
      ];
      default = "en";
      description = "Task UI language; task text and model-facing results stay unchanged.";
    };
    hideCompleted = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Hide completed widget rows on the following agent run, retaining the full task history.";
    };
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { todo = "${entry}"; });
  };
  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # Interactive session only: children are given explicit tool lists and keep to their delegated task.
    local.pi.extraSettings.extensions = [ cfg.entries.todo ];
  };
}
