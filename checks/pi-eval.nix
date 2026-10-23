{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  fixture =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [
        {
          local.pi.enable = lib.mkForce true;
          local.pi.eval.enable = lib.mkForce true;
          local.pi.codemode.enable = lib.mkForce true;
          local.pi.hashline.enable = lib.mkForce true;
          local.pi.format.enable = lib.mkForce true;
          local.pi.lsp.enable = lib.mkForce true;
        }
      ];
    }).config;
  entry = fixture.local.pi.eval.entries.eval;
  settings = fixture.programs.pi-coding-agent.settings;
  roles = [
    "build"
    "plan"
    "scout"
    "explore"
    "title"
  ];
  roleText =
    name:
    lib.attrByPath [ "${fixture.local.pi.agentDir}/agents/${name}.md" "text" ] "" fixture.home.file;
  sessionFixture = pkgs.writeText "pi-eval-fixture.json" (
    builtins.toJSON {
      evalEntry = entry;
      hashlineEntry = fixture.local.pi.hashline.entry;
      formatEntry = fixture.local.pi.format.entries.format;
      lspEntry = fixture.local.pi.lsp.entries.lsp;
      settings = fixture.local.pi.extraSettings.lsp;
      inherit (settings) defaultTools;
    }
  );
in
{
  pi-eval =
    # Interactive session only: a plain extension entry, never a required child extension, and no role grants it.
    assert lib.elem entry settings.extensions;
    assert !lib.any (child: child.path == entry) fixture.local.pi.requiredChildExtensions;
    assert lib.all (name: roleText name != "" && !lib.hasInfix "eval" (roleText name)) roles;
    # The read-only /plan toolset (used when planMode.readOnly is set) names neither the kernel nor codemode.
    assert !lib.elem "eval" fixture.local.pi.modelRoles.planMode.tools;
    assert !lib.elem "codemode" fixture.local.pi.modelRoles.planMode.tools;
    assert lib.elem "+codemode" settings.defaultTools;
    pkgs.runCommand "pi-eval-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.python3
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME" "$out"
        cd ${../.}
        PI_EVAL_PYTHON=${lib.getExe fixture.local.pi.eval.python.package} node --test tests/pi/eval-kernel.test.mjs
        timeout 600s python3 -E tests/pi/eval-session.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/session.txt"
      '';
}
