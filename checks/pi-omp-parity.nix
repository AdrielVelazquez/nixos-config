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
  pi-omp-parity =
    pkgs.runCommand "pi-omp-parity"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.git
          (pkgs.python3.withPackages (p: [
            p.pyte
            p.pillow
          ]))
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME"
        export SHELL=${lib.getExe pkgs.bash}
        export PI_UI_FONT=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf
        timeout 300s python3 -E ${../tests/pi/omp-parity-pty.py} ${lib.getExe pkgs.pi-coding-agent} \
          ${shared.contract} ${../tests/pi/omp-parity-fixture.ts} "$out"
      '';
}
