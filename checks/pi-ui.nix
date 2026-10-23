{ pkgs, homeConfigurations, ... }@args:
let
  capabilities = import ./pi.nix args;
  ui = homeConfigurations.cachyos-framework13.config.local.pi.ui;
  source = "${ui.package}/${ui.package.packageRoot}";
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
        node --test tests/pi/ui-contract.mjs tests/pi/ui-neutral-foreground.test.mjs
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
}
