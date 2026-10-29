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
      modules = [
        {
          local.pi.enable = lib.mkForce true;
          # The snapshots go where Nix says; a build can write only below /tmp.
          xdg.dataHome = lib.mkForce "/tmp/pi-checkpoints-check";
        }
      ];
    }).config;
  entry = fixture.local.pi.checkpoints.entries.checkpoints;
in
{
  # Snapshots before each prompt, /undo, /redo and the restore dialog, against real git and the real Pi in RPC mode.
  pi-checkpoints =
    assert lib.elem entry fixture.programs.pi-coding-agent.settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    assert !lib.elem entry fixture.local.pi.routing.writerExtensions;
    pkgs.runCommand "pi-checkpoints-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME" "$out"
        cd ${checkSources.pi-checkpoints}
        node --test tests/pi/checkpoint-core.test.mjs tests/pi/checkpoint.test.mjs
        timeout 400s python3 -E ${checkSources.pi-checkpoints}/tests/pi/checkpoint-session.py ${lib.getExe pkgs.pi-coding-agent} ${entry} "$out"
      '';
}
