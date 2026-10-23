{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  base = homeConfigurations.cachyos-framework13;
  fixture =
    (base.extendModules {
      modules = [
        {
          local.pi.llmPlatform.enable = lib.mkForce false;
          local.headroom.pi.enable = lib.mkForce false;
          local.tuios.integrations.pi.enable = lib.mkForce false;
          local.pi.modelRoles.roles = lib.mkForce {
            default = "fixture/primary:high";
            smol = "fixture/small:low";
            slow = "fixture/strong:high";
            plan = "fixture/strong:high";
            commit = "fixture/small:low";
            memory = "fixture/small:low";
            widget = "fixture/small:low";
            tiny = "fixture/tiny:off";
            task = "fixture/primary:high";
            advisor = "fixture/strong:high";
            vision = "fixture/vision:high";
          };
        }
      ];
    }).config;
  agentPrefix = "${fixture.local.pi.agentDir}/";
  managed = lib.filterAttrs (name: _: lib.hasPrefix agentPrefix name) fixture.home.file;
  contract = pkgs.writeText "pi-omp-parity-fixture.json" (
    builtins.toJSON {
      settingsFile = pkgs.writeText "pi-omp-parity-settings.json" (
        builtins.toJSON fixture.programs.pi-coding-agent.settings
      );
      files = lib.mapAttrs' (
        name: file: lib.nameValuePair (lib.removePrefix agentPrefix name) (toString file.source)
      ) managed;
      enabled = {
        ui = fixture.local.pi.ui.enable;
        lsp = fixture.local.pi.lsp.enable;
        ghostText = fixture.local.pi.ghostText.enable;
        modelRoles = fixture.local.pi.modelRoles.enable;
        ast = fixture.local.pi.capabilities.ast.enable;
        web = fixture.local.pi.capabilities.web.enable;
        stats = fixture.local.pi.stats.enable;
      };
    }
  );
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
          ${contract} ${../tests/pi/omp-parity-fixture.ts} "$out"
      '';
}
