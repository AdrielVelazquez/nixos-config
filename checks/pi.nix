{
  lib,
  pkgs,
  checkSources,
  homeConfigurations,
  razerHome,
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
            ui.enable = lib.mkForce false;
            capabilities = {
              ast.enable = lib.mkForce false;
              web.enable = lib.mkForce false;
            };
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
            # The provider fixture asserts the plain provider default; roles replace it with roles/auto.
            modelRoles.enable = lib.mkForce false;
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
      directRuntimePath =
        toString
          (base.extendModules {
            modules = [ { local.headroom.pi.providers.llm-platform.enable = lib.mkForce false; } ];
          }).config.local.pi.llmPlatform.runtimePackage;
    }
  );
  routed =
    (base.extendModules {
      modules = [
        {
          local.pi = {
            enable = true;
            routing.enable = true;
            modelRoles.enable = true;
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
  tuiosRecorder = pkgs.writeShellScript "pi-ui-tuios-recorder" ''
    exec ${pkgs.python3.interpreter} ${../tests/pi/tuios-recorder.py} "$@"
  '';
  tuiosRecordedHook = pkgs.runCommand "pi-ui-tuios-hook" { } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME/.pi/agent" "$out"
    ${lib.getExe' tuiosFixture.local.tuios.package "tuios"} integration install pi --command ${tuiosRecorder}
    cp "$HOME/.pi/agent/extensions/tuios-agent-state.ts" "$out/tuios-agent-state.ts"
  '';
  capabilityConfig = base.config.local.pi.capabilities or { };
  capabilityWrapperTarget = pkgs.writeShellScriptBin "pi-agentdir-witness" ''
    printf '%s\n' "$PI_CODING_AGENT_DIR"
  '';
  capabilityWrapper =
    (base.extendModules {
      modules = [ { local.pi.launcher = lib.mkForce capabilityWrapperTarget; } ];
    }).config.programs.pi-coding-agent.package;
  capabilityJSON = pkgs.writeText "pi-capabilities-contract.json" (
    builtins.toJSON {
      enabled = map (name: capabilityConfig.${name}.enable or false) [
        "ast"
        "web"
      ];
      # Effective enablement: the flags default to true, but only mean anything with local.pi.enable.
      razerEnabled =
        map (name: razerHome.local.pi.enable && (razerHome.local.pi.capabilities.${name}.enable or false))
          [
            "ast"
            "web"
          ];
      versions = map (name: capabilityConfig.${name}.package.version or null) [
        "ast"
        "web"
      ];
      entries = capabilityConfig.entries or { };
      uiEnabled = base.config.local.pi.ui.enable;
      razerUiEnabled = razerHome.local.pi.enable && razerHome.local.pi.ui.enable;
      uiEntries = base.config.local.pi.ui.entries;
      settings = base.config.programs.pi-coding-agent.settings;
      required = base.config.local.pi.requiredChildExtensions;
      files = lib.genAttrs [ "web-search.json" ] (
        name: base.config.home.file."${base.config.local.pi.agentDir}/${name}".source or null
      );
      roles = lib.genAttrs [ "build" "plan" "scout" "explore" "title" ] (
        name: base.config.home.file."${base.config.local.pi.agentDir}/agents/${name}.md".text
      );
    }
  );
  capabilityRuntimeJSON = pkgs.writeText "pi-capability-runtime.json" (
    builtins.toJSON {
      entries = capabilityConfig.entries or { };
      required = lib.filter (
        entry:
        lib.elem entry.id [
          "readonly-ast"
          "web-access"
        ]
      ) base.config.local.pi.requiredChildExtensions;
      roles = lib.genAttrs [ "build" "plan" "scout" "explore" "title" ] (
        name: base.config.home.file."${base.config.local.pi.agentDir}/agents/${name}.md".text
      );
      settingsFile = pkgs.writeText "pi-capability-settings.json" (
        builtins.toJSON {
          defaultProvider = "fixture";
          defaultModel = "unit";
          defaultThinkingLevel = "off";
          retry.enabled = false;
          compaction.enabled = false;
          extensions = [
            base.config.local.pi.ui.entries.opencodeUi
            base.config.local.pi.ui.entries.neutralForeground
          ]
          ++ builtins.attrValues (capabilityConfig.entries or { });
          theme = base.config.programs.pi-coding-agent.settings.theme or "system";
          quietStartup = base.config.programs.pi-coding-agent.settings.quietStartup or false;
          themes = base.config.programs.pi-coding-agent.settings.themes or [ ];
        }
      );
      files = lib.optionalAttrs (capabilityConfig.web.enable or false) {
        "web-search.json" = base.config.home.file."${base.config.local.pi.agentDir}/web-search.json".source;
      };
      loopback = false;
    }
  );
  capabilityLoopPolicy = lib.recursiveUpdate capabilityConfig.web.policy {
    ssrf.allowRanges = [ "127.0.0.1/32" ];
  };
  capabilityLoopEntry = pkgs.writeText "pi-test-web-access.ts" ''
    import { installWebAccess } from "${../dotfiles/pi/extensions}/web-access.ts";
    import upstream from "${capabilityConfig.web.package}/${capabilityConfig.web.package.packageRoot}/dist/index.js";
    export default pi => installWebAccess(pi, upstream, ${builtins.toJSON capabilityLoopPolicy});
  '';
  capabilityLoopJSON = pkgs.writeText "pi-capability-loopback.json" (
    builtins.toJSON {
      settingsFile = pkgs.writeText "pi-capability-loopback-settings.json" (
        builtins.toJSON {
          defaultProvider = "fixture";
          defaultModel = "unit";
          defaultThinkingLevel = "off";
          retry.enabled = false;
          compaction.enabled = false;
          extensions = builtins.attrValues (capabilityConfig.entries // { web = "${capabilityLoopEntry}"; });
          theme = base.config.programs.pi-coding-agent.settings.theme or "system";
          quietStartup = base.config.programs.pi-coding-agent.settings.quietStartup or false;
          themes = base.config.programs.pi-coding-agent.settings.themes or [ ];
        }
      );
      files = {
        "web-search.json" = pkgs.writeText "pi-test-web-policy.json" (builtins.toJSON capabilityLoopPolicy);
      };
      loopback = true;
    }
  );
  routedJSON = pkgs.writeText "pi-routed-fixture.json" (
    builtins.toJSON {
      roles = builtins.mapAttrs (
        name: _: routed.home.file."/home/adriel/.pi/agent/agents/${name}.md".text
      ) routed.local.pi.modelRoles.taskAgents;
      requiredEntry = lib.findFirst (
        path: lib.hasSuffix "pi-required-integrations.ts" path
      ) (throw "Missing required Pi policy entry") routed.programs.pi-coding-agent.settings.extensions;
    }
  );
in
{
  pi-capabilities-wrapper =
    pkgs.runCommand "pi-capabilities-wrapper"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 -E ${../tests/pi/capability-wrapper.py} ${lib.getExe' capabilityWrapper "pi"} ${lib.escapeShellArg base.config.local.pi.agentDir}
        touch "$out"
      '';
  pi-capabilities-loopback =
    pkgs.runCommand "pi-capabilities-loopback-runtime"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.git
          pkgs.ripgrep
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME"
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        node ${checkSources.pi-capabilities}/tests/pi/capabilities.mjs ${capabilityLoopJSON}
        touch "$out"
      '';
  pi-capabilities =
    pkgs.runCommand "pi-capabilities-runtime"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.git
          pkgs.ripgrep
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME"
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        node ${checkSources.pi-capabilities}/tests/pi/capabilities.mjs ${capabilityRuntimeJSON}
        touch "$out"
      '';
  pi-capabilities-contract =
    pkgs.runCommand "pi-capabilities-contract"
      {
        nativeBuildInputs = [ pkgs.nodejs_24 ];
      }
      ''
        node ${../tests/pi/capabilities-contract.mjs} ${capabilityJSON}
        touch "$out"
      '';
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
        cd ${checkSources.pi-base}
        node ${../tests/pi/workflow.mjs} ${fixtureJSON}
        node --test ${../tests/pi/question.mjs}
        touch "$out"
      '';
  pi-work =
    assert work.programs.pi-coding-agent.settings.defaultProvider == "llm-platform";
    pkgs.runCommand "pi-provider-package-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.nodejs_24
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        cd ${checkSources.pi-work}
        node --test tests/pi/headroom-llm-platform.test.mjs
        python3 -E ${../tests/pi/provider-smoke.py} ${lib.getExe pkgs.pi-coding-agent} ${workJSON}
        touch "$out"
      '';
  pi-headroom-manifest =
    pkgs.runCommand "pi-headroom-manifest-check"
      {
        __structuredAttrs = true;
        exportReferencesGraph.launcher = [ routed.local.pi.launcher ];
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 - ${lib.getExe routed.local.pi.launcher} "$NIX_ATTRS_JSON_FILE" <<'PY'
        import json
        from pathlib import Path
        import shlex
        import sys

        command = next(
            shlex.split(line)
            for line in Path(sys.argv[1]).read_text().splitlines()
            if line.startswith("exec ")
        )
        helper = command[command.index("-E") + 1]
        manifest_path = command[command.index("--config") + 1]
        manifest = json.loads(Path(manifest_path).read_text())
        graph = {
            entry["path"]: entry
            for entry in json.loads(Path(sys.argv[2]).read_text())["launcher"]
        }

        assert manifest["implementation"] == helper, "child manifest must use the launcher helper"
        assert helper in graph[manifest_path]["references"], "manifest must retain its helper"
        assert Path(helper).is_file(), "manifest helper must exist"
        PY
        touch "''${outputs[out]}"
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
        export PI_CAPABILITY_FIXTURE=${capabilityRuntimeJSON}
        cd ${checkSources.pi-headroom}
        python3 -E tests/headroom-pi.py
        node --test tests/pi/headroom-hooks.mjs tests/pi/headroom-worktrees.mjs tests/pi/headroom-children.mjs
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
        export PI_CAPABILITY_FIXTURE=${capabilityRuntimeJSON}
        export PI_HEADROOM_BACKGROUND_FACTORY=${routed.local.headroom.pi.backgroundFactory}
        export PI_SUBAGENT_ENTRY=${routed.local.pi.routing.entry}
        export PI_SUBAGENT_CONFIG=${
          routed.home.file."${routed.local.pi.agentDir}/extensions/subagent/config.json".source
        }
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        export TIKTOKEN_CACHE_DIR=${pkgs.callPackage ../packages/headroom-tokenizer-cache.nix { }}
        cd ${checkSources.pi-routing}
        node --test tests/pi/role-core.test.mjs tests/pi/model-roles.test.mjs
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
        cd ${checkSources.pi-tuios}
        node tests/pi/tuios.mjs ${tuiosJSON}
        node --test tests/pi/tuios-outcomes.mjs
        touch "$out"
      '';
}
