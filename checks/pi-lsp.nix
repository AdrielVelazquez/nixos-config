{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  base = homeConfigurations.cachyos-framework13;
  configured =
    (base.extendModules {
      modules = [
        {
          local.pi.enable = lib.mkForce true;
          local.pi.lsp.enable = lib.mkForce true;
        }
      ];
    }).config;
  disabled =
    (base.extendModules { modules = [ { local.pi.lsp.servers.gopls.enable = false; } ]; }).config;
  invalid = base.extendModules {
    modules = [
      {
        local.pi.lsp.servers.invalid = {
          command = "";
        };
      }
    ];
  };
  fixture = pkgs.writeText "pi-lsp-fixture.json" (
    builtins.toJSON {
      settings = configured.local.pi.extraSettings.lsp;
      entry = configured.local.pi.lsp.entries.lsp;
      disabledServers = builtins.attrNames disabled.local.pi.extraSettings.lsp.servers;
      missingExecutableRejected = !(builtins.tryEval invalid.activationPackage.drvPath).success;
      go = "${pkgs.go}/bin/go";
      node = "${pkgs.nodejs_24}/bin/node";
    }
  );
  package = configured.local.pi.lsp.package;
  python = pkgs.python3.withPackages (p: [
    p.pyte
    p.pillow
  ]);
in
{
  pi-lsp =
    pkgs.runCommand "pi-lsp-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          python
        ];
        LSP_PACKAGE_ROOT = "${package}/${package.packageRoot}";
        LSP_STATUS_SOURCE = "${../dotfiles/pi/extensions/lsp-status.ts}";
        PI_UI_FONT = "${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf";
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME" "$out"
        node --test ${../tests/pi/lsp-status.test.mjs} ${../tests/pi/lsp-package.test.mjs}
        python3 -E ${../tests/pi/lsp-diagnostics.py} ${lib.getExe pkgs.pi-coding-agent} ${fixture} ${../tests/pi/lsp-delay-proxy.mjs} "$out"
      '';
}
