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
          local.pi.ghostText.enable = true;
        }
      ];
    }).config;
  cfg = fixture.local.pi.ghostText;
  entry = cfg.entries.ghostText;
  wordList = toString cfg.wordList;
in
{
  pi-ghost =
    assert builtins.elem entry fixture.programs.pi-coding-agent.settings.extensions;
    assert lib.last fixture.local.pi.extraSettings.extensions == entry;
    pkgs.runCommand "pi-ghost-runtime-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.git
          (pkgs.python3.withPackages (p: [ p.pyte ]))
        ];
      }
      ''
        export HOME="$TMPDIR/home" XDG_CACHE_HOME="$TMPDIR/cache"
        export PI_OFFLINE=1 PI_TELEMETRY=0 SHELL=${lib.getExe pkgs.bash}
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        export PI_GHOST_VOCABULARY=${wordList}
        mkdir -p "$HOME" "$out"
        cd ${../.}
        node --test tests/pi/ghost-core.test.mjs tests/pi/ghost-wrapper.test.mjs tests/pi/ghost-vocabulary.test.mjs
        sha256sum ${wordList} > "$out/wordlist.sha256"
        timeout 240s python3 -E tests/pi/ghost-pty.py ${lib.getExe pkgs.pi-coding-agent} \
          ${entry} ${../tests/pi/ghost-visual-owner.ts} ${wordList} "$out"
      '';
}
