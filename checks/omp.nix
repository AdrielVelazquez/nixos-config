{
  pkgs,
  lib,
  inputs,
  homeConfigurations,
  razerHome,
  ...
}:
let
  config = homeConfigurations.cachyos-framework13.config;
  runtime = config.local.omp.runtime;
  fixture = pkgs.writeText "omp-runtime-fixture.json" (
    builtins.toJSON {
      omp = lib.getExe' runtime.raw "omp";
      python = pkgs.python3.interpreter;
      helper = "${../packages/headroom-pi.py}";
      entrySource = "${../dotfiles/omp}/work.ts";
      mcpFixture = "${../tests/omp/mcp-native.ts}";
      projectOptionsSource = "${runtime.ocProviderSource}/src/options.mjs";
      wrapper = lib.getExe runtime.wrapper;
      piAgentDir = config.local.pi.agentDir;
      modelsFile = toString config.home.file.".omp/agent/models.yml".source;
      tuiosFile = toString config.home.file.".omp/agent/extensions/tuios-omp-agent-state.ts".source;
      githubAuth = lib.removePrefix "!" runtime.mcp.mcpServers.github.headers.Authorization;
      inherit (runtime) settings routes;
      agents = lib.genAttrs [ "build" "plan" "scout" "explore" ] (
        name: config.home.file.".omp/agent/agents/${name}.md".text
      );
    }
  );
  contract = pkgs.writeText "omp-config-fixture.json" (
    builtins.toJSON {
      enabled = config.programs.omp.enable;
      razerEnabled = razerHome.programs.omp.enable;
      piEnabled = config.local.pi.enable;
      ocEnabled = config.programs.opencode.enable;
      ocAlias = config.programs.zsh.shellAliases.oc;
      inherit (runtime) settings mcp manifest;
      projectOptionsSource = "${runtime.ocProviderSource}/src/options.mjs";
      inherit (runtime) ocPluginOptions;
      redditEnabled = config.local.omp.reddit.enable;
      redditControlPlaneOrigin = config.local.omp.reddit.controlPlaneOrigin;
      redditSupport = runtime.redditSupport;
      ocProviderPlugin = config.local.opencode.llmPlatform.plugin;
      mainConfigSymlink = config.home.file ? ".omp/agent/config.yml";
      activation = config.home.activation.ompConfig.data;
      skills = map (name: toString config.home.file.".omp/agent/skills/${name}".source) [
        "ce-compound"
        "ce-compound-refresh"
        "openspec-propose"
        "openspec-explore"
        "openspec-apply-change"
        "openspec-update-change"
        "openspec-sync-specs"
        "openspec-archive-change"
      ];
      commands = map (name: toString config.home.file.".omp/agent/commands/opsx-${name}.md".source) [
        "propose"
        "explore"
        "apply"
        "update"
        "sync"
        "archive"
      ];
      context = config.home.file.".omp/agent/AGENTS.md".text;
      tuiosFile = toString config.home.file.".omp/agent/extensions/tuios-omp-agent-state.ts".source;
    }
  );
in
{
  omp-config =
    pkgs.runCommand "omp-native-config-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
      ''
        node ${../tests/omp/config.mjs} ${contract}
        touch "$out"
      '';
  omp-core =
    pkgs.runCommand "omp-provider-policy-leases"
      {
        nativeBuildInputs = [
          pkgs.nodejs_24
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        cd ${../.}
        node --test tests/omp/provider.mjs tests/omp/policy.mjs tests/omp/extension.mjs
        python3 -E tests/headroom-omp.py
        python3 -E tests/headroom-pi.py
        touch "$out"
      '';
  omp-reddit-core =
    pkgs.runCommand "omp-reddit-services-check" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
      ''
        cd ${../.}
        export OMP_REDDIT_SUPPORT=${inputs.pi-reddit-provider}/src
        node --test tests/omp/reddit-services.mjs
        touch "$out"
      '';
  omp-wire =
    pkgs.runCommand "omp-native-provider-wire"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
          pkgs.ripgrep
        ];
      }
      ''
        python3 -E ${../tests/omp/wire.py} ${fixture}
        touch "$out"
      '';
  omp-mcp =
    pkgs.runCommand "omp-native-owned-mcp"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        python3 -E ${../tests/omp/mcp-native.py} ${fixture}
        touch "$out"
      '';
  omp-mcp-auth =
    pkgs.runCommand "omp-native-owned-mcp-auth"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        python3 -E ${../tests/omp/mcp-auth.py} ${fixture}
        touch "$out"
      '';
  omp-mcp-auth-invalid =
    pkgs.runCommand "omp-native-owned-mcp-auth-invalid"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        python3 -E ${../tests/omp/mcp-auth.py} ${fixture} --bad-issuer
        python3 -E ${../tests/omp/mcp-auth.py} ${fixture} --bad-resource
        touch "$out"
      '';
  omp-mcp-xdev =
    pkgs.runCommand "omp-native-owned-mcp-xdev"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        python3 -E ${../tests/omp/mcp-native.py} ${fixture} --xdev
        touch "$out"
      '';
  omp-mcp-lifecycle =
    pkgs.runCommand "omp-native-owned-mcp-lifecycle"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.git
        ];
      }
      ''
        python3 -E ${../tests/omp/mcp-native.py} ${fixture} --lifecycle
        touch "$out"
      '';
}
