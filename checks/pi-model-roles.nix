{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  home = homeConfigurations.cachyos-framework13.config;
  cfg = home.local.pi.modelRoles;
  partial =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [
        {
          local.pi.modelRoles.roles.vision = lib.mkForce "fixture/image:high";
          local.pi.modelRoles.taskAgents.build = lib.mkForce "@slow";
          local.pi.modelRoles.planMode.instructions = lib.mkForce "Explicit planning override.";
        }
      ];
    }).config.local.pi.modelRoles;
  defaults = {
    modelRoles = cfg.roles;
    retry = { inherit (cfg) modelFallback cooldownMs fallbackChains; };
    inherit (cfg) compactionRole planMode;
  };
  contract = pkgs.writeText "pi-model-roles-contract.json" (
    builtins.toJSON {
      settings = home.programs.pi-coding-agent.settings;
      options = defaults;
      partialRoles = partial.roles;
      partialAgents = partial.taskAgents;
      partialInstructions = partial.planMode.instructions;
      entry = cfg.entries.modelRoles;
      roles = lib.genAttrs (builtins.attrNames cfg.taskAgents) (
        name: home.home.file."${home.local.pi.agentDir}/agents/${name}.md".text
      );
    }
  );
  fixtureEntry = pkgs.writeText "pi-model-roles-fixture.ts" ''
    import { createModelRoles } from "${../dotfiles/pi/extensions}/model-roles.ts";
    export default pi => createModelRoles(pi, ${
      builtins.toJSON {
        modelRoles = {
          default = "fixture/primary:high";
          smol = "fixture/strong:low";
          slow = "fixture/strong:high";
          plan = "@slow";
          vision = "fixture/strong:high";
        };
        retry = {
          modelFallback = true;
          cooldownMs = 2000;
          fallbackChains.default = [ "fixture/small:off" ];
        };
        autoTitle = false;
      }
    });
  '';
in
{
  pi-model-roles =
    pkgs.runCommand "pi-model-roles-runtime-check"
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
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        export PI_UI_FONT=${pkgs.dejavu_fonts}/share/fonts/truetype/DejaVuSansMono.ttf
        cd ${../.}
        node --test tests/pi/role-core.test.mjs tests/pi/model-roles.test.mjs
        node tests/pi/model-roles-contract.mjs ${contract}
        python3 -E tests/pi/model-roles-pty.py ${lib.getExe pkgs.pi-coding-agent} ${fixtureEntry} ${../tests/pi/model-roles-fixture.ts} "$out"
      '';
}
