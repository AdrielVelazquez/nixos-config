{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  shared = import ./pi-managed-fixture.nix { inherit lib pkgs homeConfigurations; };
in
{
  pi-settings =
    pkgs.runCommand "pi-settings-check"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME" "$out"
        python3 -E ${../tests/pi/writable-settings.py} ${lib.getExe pkgs.pi-coding-agent} ${shared.contract}
      '';
}
