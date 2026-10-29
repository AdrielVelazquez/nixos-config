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
  # Exercise the packaged upstream extension in real Pi, including automatic wake-ups and process cleanup.
  pi-jobs =
    assert lib.elem entry fixture.programs.pi-coding-agent.settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    assert !lib.elem entry fixture.local.pi.routing.writerExtensions;
    pkgs.runCommand "pi-jobs-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME" "$out"
        timeout 400s python3 -BE ${checkSources.pi-jobs}/tests/pi/jobs-session.py ${lib.getExe pkgs.pi-coding-agent} ${entry} "$out"
      '';
}
