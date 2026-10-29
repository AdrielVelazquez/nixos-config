{
  lib,
  pkgs,
  checkSources,
  homeConfigurations,
  ...
}:
let
  fixture =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [ { local.pi.enable = lib.mkForce true; } ];
    }).config;
  entry = fixture.local.pi.jobs.entries.jobs;
in
{
  # The job tool against real processes: the manager, the tool wiring against a fake Pi, and real Pi through start,
  # a waiting read, a cursor read, stop and the cleanup when the session ends.
  pi-jobs =
    assert lib.elem entry fixture.programs.pi-coding-agent.settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    assert !lib.elem entry fixture.local.pi.routing.writerExtensions;
    pkgs.runCommand "pi-jobs-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.python3
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME" "$out"
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        cd ${checkSources.pi-jobs}
        node --test tests/pi/job-core.test.mjs tests/pi/job.test.mjs
        timeout 400s python3 -E ${checkSources.pi-jobs}/tests/pi/jobs-session.py ${lib.getExe pkgs.pi-coding-agent} ${entry} "$out"
      '';
}
