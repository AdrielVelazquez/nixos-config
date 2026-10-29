{
  lib,
  pkgs,
  homeConfigurations,
  razerHome,
  ...
}:
let
  host = homeConfigurations.cachyos-framework13;
  off = {
    openai-codex.enable = lib.mkForce false;
    opencode-go.enable = lib.mkForce false;
    llm-platform.enable = lib.mkForce false;
  };
  fixture =
    providers: extra:
    (host.extendModules {
      modules = [
        { local.headroom.pi.providers = off // providers; }
        extra
      ];
    }).config;
  base = fixture { } { };
  configured = fixture {
    openai-codex.enable = lib.mkForce true;
    opencode-go.enable = lib.mkForce true;
    llm-platform.enable = lib.mkForce true;
  } { };
  summary = config: {
    adapters = config.local.headroom.pi.adapters;
    required = config.local.pi.requiredChildExtensions;
    entries = lib.filter (
      path: lib.hasSuffix "pi-headroom-providers.ts" path || lib.hasSuffix "pi-headroom-codex.ts" path
    ) config.programs.pi-coding-agent.settings.extensions;
    llmPlatform = config.local.pi.llmPlatform.enable;
    assertions = map (entry: entry.assertion) config.assertions;
  };
  contractJSON = pkgs.writeText "pi-headroom-providers-contract.json" (
    builtins.toJSON {
      configured = summary configured;
      unconfigured = summary base;
      codexOnly = summary (fixture { openai-codex.enable = lib.mkForce true; } { });
      goOnly = summary (fixture { opencode-go.enable = lib.mkForce true; } { });
      llmOnly = summary (fixture { llm-platform.enable = lib.mkForce true; } { });
      globalOff = summary (
        fixture {
          openai-codex.enable = lib.mkForce true;
          opencode-go.enable = lib.mkForce true;
          llm-platform.enable = lib.mkForce true;
        } { local.headroom.pi.enable = lib.mkForce false; }
      );
      llmAbsent = summary (
        fixture { llm-platform.enable = lib.mkForce true; } {
          local.pi.llmPlatform.enable = lib.mkForce false;
        }
      );
      framework = summary host.config;
      razer = summary razerHome;
    }
  );
  rawHeadroom = base.local.headroom.package.unwrapped;
  codexProxy = pkgs.writeShellScript "headroom-codex-fixture" ''
    export PYTHONPATH="${rawHeadroom}/${pkgs.python3.sitePackages}:${pkgs.python3Packages.makePythonPath (pkgs.python3Packages.requiredPythonModules rawHeadroom.dependencies)}"
    exec ${pkgs.python3.interpreter} ${../tests/pi/headroom-codex-proxy.py} "$@"
  '';
in
{
  pi-headroom-providers-contract =
    pkgs.runCommand "pi-headroom-providers-contract" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
      ''
        node ${../tests/pi/headroom-providers-contract.mjs} ${contractJSON}
        touch "$out"
      '';
  pi-headroom-codex =
    pkgs.runCommand "pi-headroom-codex-runtime-check"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.nodejs_24
          pkgs.git
        ];
      }
      ''
        export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
        mkdir -p "$HOME"
        export PI_TEST_PACKAGE_DIR="${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo"
        cd ${../.}
        node --test tests/pi/headroom-codex.test.mjs
        node tests/pi/headroom-codex.mjs ${pkgs.python3.interpreter} ${codexProxy} \
          ${lib.getExe pkgs.pi-coding-agent} ${
            pkgs.callPackage ../packages/headroom-tokenizer-cache.nix { }
          }
        touch "$out"
      '';
  pi-headroom-providers =
    pkgs.runCommand "pi-headroom-providers-runtime-check"
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
        node --test tests/pi/headroom-providers.test.mjs tests/pi/headroom-hooks.mjs
        node tests/pi/headroom-providers.mjs ${pkgs.python3.interpreter} ${lib.getExe base.local.headroom.package} \
          ${lib.getExe pkgs.pi-coding-agent} ${
            pkgs.callPackage ../packages/headroom-tokenizer-cache.nix { }
          }
        touch "$out"
      '';
}
