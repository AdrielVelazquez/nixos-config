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
          local.pi.format.enable = lib.mkForce true;
          local.pi.lsp.enable = lib.mkForce true;
        }
      ];
    }).config;
  entry = fixture.local.pi.format.entries.format;
  lspEntry = fixture.local.pi.lsp.entries.lsp;
  extensions = fixture.programs.pi-coding-agent.settings.extensions;
  indexOf = value: lib.lists.findFirstIndex (candidate: candidate == value) null extensions;
  orderFixture = pkgs.writeText "pi-format-order-fixture.json" (
    builtins.toJSON {
      formatEntry = entry;
      inherit lspEntry;
      settings = fixture.local.pi.extraSettings.lsp;
    }
  );
  astFixture = pkgs.writeText "pi-ast-rewrite-fixture.json" (
    builtins.toJSON {
      formatEntry = entry;
      astEntries = [
        fixture.local.pi.capabilities.entries.ast
        fixture.local.pi.capabilities.entries.astRewrite
      ];
    }
  );
in
{
  pi-format =
    # The formatter must run first so the LSP's post-edit diagnostics read the formatted file.
    assert indexOf entry != null && indexOf lspEntry != null && indexOf entry < indexOf lspEntry;
    assert lib.any (
      child: child.id == "format-on-write" && child.path == entry
    ) fixture.local.pi.requiredChildExtensions;
    pkgs.runCommand "pi-format-check"
      {
        nativeBuildInputs = [
          pkgs.git
          pkgs.nodejs_24
          pkgs.python3
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        mkdir -p "$HOME" "$out"
        cd ${../.}
        node --test tests/pi/format-core.test.mjs tests/pi/format-on-write.test.mjs tests/pi/bash-changes.test.mjs
        node tests/pi/format-contract.mjs ${entry} | tee "$out/contract.txt"
        timeout 280s python3 -E tests/pi/bash-format-session.py ${lib.getExe pkgs.pi-coding-agent} ${orderFixture} "$out/bash" | tee "$out/bash.txt"
        timeout 280s python3 -E tests/pi/format-order.py ${lib.getExe pkgs.pi-coding-agent} ${orderFixture} "$out" | tee "$out/order.txt"
        timeout 280s python3 -E tests/pi/ast-rewrite-format.py ${lib.getExe pkgs.pi-coding-agent} ${astFixture} "$out" | tee "$out/ast-rewrite.txt"
      '';
}
