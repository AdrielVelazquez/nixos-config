{ pkgs, homeConfigurations, ... }@args:
let
  capabilities = import ./pi.nix args;
  ui = homeConfigurations.cachyos-framework13.config.local.pi.ui;
  source = "${ui.package}/${ui.package.packageRoot}";
  home = homeConfigurations.cachyos-framework13.config;
  # Only the visual surface: the managed entries, theme list and tool set the preview depends on, nothing that
  # needs a network, a secret or a provider.
  opencodeSettings = pkgs.writeText "pi-opencode-ui-settings.json" (
    builtins.toJSON {
      inherit (home.programs.pi-coding-agent.settings) theme themes quietStartup;
      extensions = [
        ui.entries.opencodeUi
        ui.entries.neutralForeground
        home.local.pi.todo.entries.todo
      ];
      defaultTools = [
        "+find"
        "+ls"
        "+grep"
      ];
      hideThinkingBlock = false;
      enableAnalytics = false;
      enableInstallTelemetry = false;
    }
  );
in
{
  pi-ui =
    pkgs.runCommand "pi-ui"
      {
        nativeBuildInputs = [ pkgs.nodejs_24 ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME"
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        cd ${../.}
        node --test tests/pi/ui-contract.mjs tests/pi/ui-neutral-foreground.test.mjs tests/pi/opencode-ui.test.mjs
        node --input-type=module - ${source} <<'JS'
        import assert from 'node:assert/strict';
        import { readFileSync } from 'node:fs';
        const root = process.argv[2];
        const pkg = JSON.parse(readFileSync(root + '/package.json', 'utf8'));
        assert.equal(pkg.version, '1.0.26');
        assert.deepEqual(pkg.dependencies ?? {}, {});
        for (const key of ['install', 'postinstall', 'prepare']) assert.equal(pkg.scripts?.[key], undefined);
        const source = readFileSync(root + '/dist/extensions/pi-omp-theme.ts', 'utf8');
        assert.ok(source.includes('if (style === "boxed" && frame !== "rounded") return "boxed";'), 'rounded boxed frame correction is installed');
        assert.ok(source.includes('return super.handleMouse({ ...event, x: event.x - offset, width });'), 'editor mouse geometry correction is installed');
        JS
        test -e ${capabilities.pi-capabilities-contract}
        mkdir -p "$out"
        cp -R ${capabilities.pi-capabilities-ui}/. "$out/"
      '';
  # Real Pi in a PTY with the managed opencode skin and a scripted provider: asserts the prompt panel, header,
  # footer, inline tool lines, diff and shell blocks, answer footer and that no text falls back to the terminal's
  # default foreground. The PNG captures in $out are the visual record.
  pi-ui-opencode =
    pkgs.runCommand "pi-ui-opencode"
      {
        nativeBuildInputs = [
          (pkgs.python3.withPackages (p: [
            p.pyte
            p.pillow
          ]))
          pkgs.nodejs_24
          pkgs.git
        ];
      }
      ''
        export SHELL=${pkgs.lib.getExe pkgs.bash}
        export PI_UI_FONT=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf
        timeout 240s python3 ${../tests/pi/ui-preview}/preview.py --pi ${pkgs.lib.getExe pkgs.pi-coding-agent} \
          --settings ${opencodeSettings} --out "$out" --cols 110 --rows 96 --narrow 80 --check
      '';
}
