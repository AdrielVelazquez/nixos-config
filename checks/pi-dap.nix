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
          local.pi.dap.enable = lib.mkForce true;
        }
      ];
    }).config;
  settings = fixture.programs.pi-coding-agent.settings;
  entry = fixture.local.pi.dap.entry;
  roleText =
    name:
    lib.attrByPath [
      "${fixture.local.pi.agentDir}/agents/${name}.md"
      "text"
    ] "" fixture.home.file;
  roles = [
    "build"
    "plan"
    "scout"
    "explore"
    "title"
  ];
  sessionFixture = pkgs.writeText "pi-dap-fixture.json" (
    builtins.toJSON {
      inherit entry;
      inherit (settings) dap;
      # What a project's own environment would put on PATH: compilers for the programs under debug.
      path = lib.makeBinPath [
        pkgs.nodejs_24
        pkgs.go
        pkgs.gcc
        pkgs.coreutils
      ];
      rustc = lib.getExe' pkgs.rustc "rustc";
    }
  );
in
{
  pi-dap =
    # Interactive session only: children never load the DAP entry, and no role grants a dap_* tool.
    assert lib.elem entry settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    assert lib.all (name: roleText name != "" && !lib.hasInfix "dap_" (roleText name)) roles;
    pkgs.runCommand "pi-dap-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME" "$out"
      cd ${checkSources.pi-dap}
      timeout 600s python3 -E tests/pi/dap-session.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/session.txt"
    '';
}
