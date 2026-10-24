{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.checkpoints;
  entry = piLib.mkEntry {
    name = "pi-checkpoints.ts";
    module = "checkpoint";
    factory = "createCheckpoints";
    args = {
      git = lib.getExe pkgs.git;
      # One private repository per project, outside every working tree.
      dataDir = "${config.xdg.dataHome}/pi/checkpoints";
      inherit (cfg)
        maxFiles
        maxFileBytes
        maxAgeDays
        restoreOnTree
        ;
    };
  };
in
{
  options.local.pi.checkpoints = {
    enable = piLib.mkFeatureEnable "a working-tree snapshot before every prompt, with /undo, /redo and /checkpoints";
    maxFiles = lib.mkOption {
      type = lib.types.ints.positive;
      default = 50000;
      description = "A project with more files than this is not checkpointed: the first snapshot would hash them all.";
    };
    maxFileBytes = lib.mkOption {
      type = lib.types.ints.positive;
      default = 5 * 1024 * 1024;
      description = "Files larger than this stay out of snapshots and are never touched by a restore.";
    };
    maxAgeDays = lib.mkOption {
      type = lib.types.ints.positive;
      default = 14;
      description = "Snapshots older than this are dropped when a session starts.";
    };
    restoreOnTree = lib.mkOption {
      type = lib.types.enum [
        "ask"
        "never"
      ];
      default = "ask";
      description = "`ask` offers to restore the files when `/tree` moves the conversation to an earlier point; `never` leaves that to /undo and /checkpoints.";
    };
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { checkpoints = "${entry}"; });
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # Interactive session only: children work from the checkpoints of the session that started them.
    local.pi.extraSettings.extensions = [ cfg.entries.checkpoints ];
  };
}
