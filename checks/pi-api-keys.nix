{
  lib,
  pkgs,
  homeConfigurations,
  ...
}:
let
  base = homeConfigurations.cachyos-framework13;
  secretPath = "/tmp/pi-api-key-fixture";
  fixture =
    (base.extendModules {
      modules = [
        {
          local.pi.apiKeys = {
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
      unconfiguredHasModels = base.config.home.file ? "${agentDir}/models.json";
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
