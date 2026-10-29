{
  config,
  lib,
  pkgs,
  piLib,
  ...
}:
let
  cfg = config.local.pi.jobs;
  package = pkgs.callPackage ../../../packages/pi-background.nix { };
  entry = "${package}/${package.packageRoot}/extensions/background.ts";
in
{
  imports =
    map
      (
        name:
        lib.mkRemovedOptionModule [ "local" "pi" "jobs" name ]
          "Managed jobs now use upstream pi-background, which does not support this setting. See docs/pi-jobs.md."
      )
      [
        "maxJobs"
        "maxBufferKiB"
        "notifyOnExit"
      ];

  options.local.pi.jobs = {
    enable = piLib.mkFeatureEnable "upstream background jobs with automatic completion wake-ups";
    entries = piLib.mkEntriesOption (lib.optionalAttrs cfg.enable { jobs = entry; });
  };

  config = lib.mkIf (config.local.pi.enable && cfg.enable) {
    # Interactive session only: a job runs with the user's authority like bash, and the read-only roles have no shell.
    local.pi.extraSettings.extensions = [ cfg.entries.jobs ];
  };
}
