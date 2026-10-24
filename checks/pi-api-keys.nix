{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  # The host decides its own apiKeys (Framework currently trials opencode-go); the check states both cases itself.
  base =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [ { local.pi.apiKeys = lib.mkForce { }; } ];
    }).config;
  secretPath = "/tmp/pi-api-key-fixture";
  fixture =
    (homeConfigurations.cachyos-framework13.extendModules {
      modules = [
        {
          local.pi.apiKeys = lib.mkForce {
            opencode-go = "opencode_api_key";
            opencode = "opencode_api_key";
          };
          sops.secrets.opencode_api_key.path = lib.mkForce secretPath;
        }
      ];
    }).config;
  agentDir = fixture.local.pi.agentDir;
  fixtureJSON = pkgs.writeText "pi-api-keys-fixture.json" (
    builtins.toJSON {
      modelsFile = toString fixture.home.file."${agentDir}/models.json".source;
      inherit secretPath;
      secrets = builtins.attrNames (
        lib.filterAttrs (name: _: name == "opencode_api_key") fixture.sops.secrets
      );
      unconfiguredHasModels = base.home.file ? "${agentDir}/models.json";
    }
  );
in
{
  pi-api-keys =
    pkgs.runCommand "pi-api-keys-runtime-check"
      {
        nativeBuildInputs = [ pkgs.nodejs_24 ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        export PI_OFFLINE=1 PI_TELEMETRY=0
        node ${../tests/pi/api-keys.mjs} ${fixtureJSON} ${lib.getExe pkgs.pi-coding-agent}
        touch "$out"
      '';
}
