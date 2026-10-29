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
      inherit todoEntry;
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
          pkgs.python3
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME" "$out"
        cd ${checkSources.pi-tools}
        node --test tests/pi/todo-core.test.mjs
        timeout 400s python3 -E tests/pi/tools-session.py ${lib.getExe pkgs.pi-coding-agent} ${sessionFixture} "$out" | tee "$out/session.txt"
      '';
}
