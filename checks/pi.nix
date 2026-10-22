{
  lib,
  pkgs,
  homeConfigurations,
  inputs,
  ...
}:
let
  base = homeConfigurations.cachyos-framework13;
  fixture =
    (base.extendModules {
      modules = [
        {
          local.pi = {
            enable = lib.mkForce true;
            llmPlatform.enable = lib.mkForce false;
            routing.enable = lib.mkForce false;
            workflow.enable = lib.mkForce true;
            openspec.enable = lib.mkForce true;
          };
          local.headroom.pi.enable = lib.mkForce false;
          local.tuios.integrations.pi.enable = lib.mkForce false;
        }
      ];
    }).config;
  fixtureJSON = pkgs.writeText "pi-workflow-fixture.json" (
    builtins.toJSON {
      settings = fixture.programs.pi-coding-agent.settings;
      mcpFile = toString fixture.home.file."/home/adriel/.pi/agent/mcp.json".source;
    }
  );
  work =
    (base.extendModules {
      modules = [
        {
          local.pi = {
            enable = true;
            llmPlatform = {
              enable = true;
              package = inputs.pi-reddit-provider.outPath;
              cli.enable = true;
            };
          };
        }
      ];
    }).config;
  workJSON = pkgs.writeText "pi-provider-fixture.json" (
    builtins.toJSON {
      runtimePath = toString work.local.pi.llmPlatform.runtimePackage;
    }
  );
  routed =
    (base.extendModules {
      modules = [
        {
          local.pi = {
            enable = true;
            routing = {
              enable = true;
              agents = {
                plan = {
                  model = "llm-platform/claude-sonnet-5-5";
                  thinking = "xhigh";
                };
                build = {
                  model = "llm-platform/gpt-6.1-sol";
                  thinking = "high";
                };
                scout = {
                  model = "llm-platform/gpt-6.1-sol";
                  thinking = "low";
                };
                explore = {
                  model = "llm-platform/gpt-6-luna";
                  thinking = "low";
                };
                title = {
                  model = "llm-platform/gpt-6-luna";
                  thinking = "low";
                };
              };
            };
          };
          local.headroom.pi.adapters.fixture = {
            urlEnv = "FIXTURE_PROXY";
            requiredEnv = "FIXTURE_REQUIRED";
            upstreamOrigins = [ "https://fixture.invalid" ];
          };
          local.headroom.pi.enable = true;
        }
      ];
    }).config;
  subagents = routed.local.pi.routing.package;
  subagentsRoot = "${subagents}/${subagents.packageRoot}";
  tuiosFixture =
    (base.extendModules {
      modules = [
        {
          local.pi.enable = lib.mkForce true;
          local.tuios.integrations.pi.enable = lib.mkForce true;
        }
      ];
    }).config;
  tuiosJSON = pkgs.writeText "pi-tuios-fixture.json" (
    builtins.toJSON {
      entry =
        toString
          tuiosFixture.home.file."/home/adriel/.pi/agent/extensions/tuios-agent-state.ts".source;
      tuios = lib.getExe' tuiosFixture.local.tuios.package "tuios";
    }
  );
  routedJSON = pkgs.writeText "pi-routed-fixture.json" (
    builtins.toJSON {
      roles = builtins.mapAttrs (
        name: _: routed.home.file."/home/adriel/.pi/agent/agents/${name}.md".text
      ) routed.local.pi.routing.agents;
      requiredEntry = lib.findFirst (
        path: lib.hasSuffix "pi-required-integrations.ts" path
      ) (throw "Missing required Pi policy entry") routed.programs.pi-coding-agent.settings.extensions;
    }
  );
in
{
  pi-base =
    assert fixture.programs.pi-coding-agent.enable;
    assert
      builtins.length (
        lib.filter (package: (package.pname or "") == "pi-coding-agent") fixture.home.packages
      ) == 1;
    pkgs.runCommand "pi-base-workflow-check"
      {
        nativeBuildInputs = [ pkgs.nodejs_24 ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export PI_OFFLINE=1 PI_TELEMETRY=0
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        cd ${../.}
        node ${../tests/pi/workflow.mjs} ${fixtureJSON}
        node --test ${../tests/pi/question.mjs}
        touch "$out"
      '';
  pi-work =
    assert work.programs.pi-coding-agent.settings.defaultProvider == "llm-platform";
    pkgs.runCommand "pi-provider-package-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
      export HOME="$TMPDIR/home"
      mkdir -p "$HOME"
      python3 -E ${../tests/pi/provider-smoke.py} ${lib.getExe pkgs.pi-coding-agent} ${workJSON}
      touch "$out"
    '';
  pi-headroom =
    pkgs.runCommand "pi-headroom-runtime-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.nodejs_24
          pkgs.git
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export PI_OFFLINE=1 PI_TELEMETRY=0
        cd ${../.}
        python3 -E tests/headroom-pi.py
        node --test tests/pi/headroom-hooks.mjs
        for model in claude-sonnet-5-5 gpt-5.5; do
          PI_STACK_MODEL="$model" node tests/pi/headroom.mjs \
            ${pkgs.python3.interpreter} ${lib.getExe base.config.local.headroom.package} \
            ${lib.getExe pkgs.pi-coding-agent} ${inputs.pi-reddit-provider}/dev/local/index.ts \
            ${inputs.superpowers}/.pi/extensions/superpowers.ts ${
              pkgs.callPackage ../packages/headroom-tokenizer-cache.nix { }
            }
        done
        touch "$out"
      '';
  pi-routing =
    pkgs.runCommand "pi-routing-runtime-check"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export PI_OFFLINE=1 PI_TELEMETRY=0
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        export TIKTOKEN_CACHE_DIR=${pkgs.callPackage ../packages/headroom-tokenizer-cache.nix { }}
        cd ${../.}
        node --test tests/pi/primary-routing.mjs
        node tests/pi/roles.mjs ${subagentsRoot} ${routedJSON}
        node tests/pi/required-integrations.mjs ${subagentsRoot} ${routedJSON}
        node tests/pi/routing.mjs ${lib.getExe pkgs.pi-coding-agent} ${subagentsRoot} ${inputs.pi-reddit-provider}/dev/local/index.ts \
          ${pkgs.python3.interpreter} ${lib.getExe base.config.local.headroom.package}
        touch "$out"
      '';
  pi-tuios =
    pkgs.runCommand "pi-tuios-integration-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export PI_OFFLINE=1 PI_TELEMETRY=0
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        cd ${../.}
        node tests/pi/tuios.mjs ${tuiosJSON}
        node --test tests/pi/tuios-outcomes.mjs
        touch "$out"
      '';
}
