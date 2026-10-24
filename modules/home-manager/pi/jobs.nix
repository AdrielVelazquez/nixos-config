{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.jobs;
  entry = piLib.mkEntry {
    name = "pi-jobs.ts";
    module = "job";
    factory = "createJobs";
    args = {
      shell = [
        (lib.getExe pkgs.bash)
        "-c"
      ];
      # The working directory is the session's own; this default is only for a manager made before one exists.
      cwd = config.home.homeDirectory;
      inherit (cfg) maxJobs notifyOnExit;
      maxBuffer = cfg.maxBufferKiB * 1024;
    };
  };
in
{
  options.local.pi.jobs = {
    enable = piLib.mkFeatureEnable "the `job` tool: commands that keep running in the background while the session goes on";
    maxJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 8;
      description = "Most jobs running at once.";
    };
    maxBufferKiB = lib.mkOption {
      type = lib.types.ints.positive;
      default = 1024;
      description = "Output kept per job; older output is dropped.";
    };
    notifyOnExit = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Announce a job in the session when it ends.";
    };
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { jobs = "${entry}"; });
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # Interactive session only: a job runs with the user's authority like bash, and the read-only roles have no shell.
    local.pi.extraSettings.extensions = [ cfg.entries.jobs ];
  };
}
