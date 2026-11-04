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
  packageRoot = builtins.dirOf (builtins.dirOf entry);
  sdk = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo";
in
{
  # Exercise the packaged upstream extension in real Pi, including automatic wake-ups and process cleanup.
  pi-jobs =
    assert lib.elem entry fixture.programs.pi-coding-agent.settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    assert !lib.elem entry fixture.local.pi.routing.writerExtensions;
    pkgs.runCommand "pi-jobs-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.nodejs_24
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME" "$out"
        timeout 400s python3 -BE ${checkSources.pi-jobs}/tests/pi/jobs-session.py ${lib.getExe pkgs.pi-coding-agent} ${entry} "$out"
        cp -R ${packageRoot} "$TMPDIR/navigation"
        chmod u+w "$TMPDIR/navigation/node_modules"
        ln -s ${sdk}/node_modules/jiti "$TMPDIR/navigation/node_modules/jiti"
        timeout 30s node --test "$TMPDIR/navigation/tests/"*.test.mjs
      '';
}
