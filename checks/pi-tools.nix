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
        }
      ];
    }).config;
  settings = fixture.programs.pi-coding-agent.settings;
  todoEntry = fixture.local.pi.todo.entries.todo;
  todoUiEntry =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [
        {
          local.pi.todo.maxWidgetLines = lib.mkForce 5;
          local.pi.todo.locale = lib.mkForce "fr";
          local.pi.todo.hideCompleted = lib.mkForce true;
        }
      ];
    }).config.local.pi.todo.entries.todo;
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
  sessionFixture = pkgs.writeText "pi-tools-fixture.json" (
    builtins.toJSON {
      inherit (settings) defaultTools;
      inherit todoEntry todoUiEntry;
      evalEntry = fixture.local.pi.eval.entries.eval;
      uiEntries = [
        fixture.local.pi.ui.entries.opencodeUi
        fixture.local.pi.ui.entries.neutralForeground
      ];
    }
  );
in
{
  pi-tools =
    # Pi starts with read, bash, edit and write; the managed selection adds the read-only discovery tools.
    assert lib.elem "+find" settings.defaultTools && lib.elem "+ls" settings.defaultTools;
    # The task list is a plain extension of the interactive session: not a required child extension, and no role
    # file names it. The read-only /plan toolset keeps it.
    assert lib.elem todoEntry settings.extensions;
    assert !lib.any (child: child.path == todoEntry) fixture.local.pi.requiredChildExtensions;
    assert lib.all (name: roleText name != "" && !lib.hasInfix "todo" (roleText name)) roles;
    assert lib.elem "todo" fixture.local.pi.modelRoles.planMode.tools;
    pkgs.runCommand "pi-tools-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          (pkgs.python3.withPackages (p: [ p.pyte ]))
        ];
      }
      ''
        export HOME="$TMPDIR/home" PYTHONDONTWRITEBYTECODE=1
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        mkdir -p "$HOME" "$out"
        cd ${checkSources.pi-tools}
        node --test tests/pi/todo-core.test.mjs tests/pi/todo-features.test.mjs tests/pi/todo.test.mjs
        timeout 400s python3 -B -E tests/pi/tools-session.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/session.txt"
        timeout 240s python3 -B -E tests/pi/todo-session.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/todo-session.txt"
        timeout 120s python3 -B -E tests/pi/todo-ui.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/todo-ui.txt"
      '';
}
