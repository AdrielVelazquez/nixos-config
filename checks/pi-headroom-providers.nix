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
        { local.headroom.pi.providers."opencode-go" = "https://opencode.ai/inference/go/v1"; }
      ];
    }).config;
  summary =
    config:
    let
      entry = lib.findFirst (
        path: lib.hasSuffix "pi-headroom-providers.ts" path
      ) null config.programs.pi-coding-agent.settings.extensions;
    in
    {
      adapters = config.local.headroom.pi.adapters;
      required = config.local.pi.requiredChildExtensions;
      inherit entry;
    };
  contractJSON = pkgs.writeText "pi-headroom-providers-contract.json" (
    builtins.toJSON {
      configured = summary configured;
      unconfigured = summary base.config;
    }
  );
in
{
  pi-headroom-providers-contract =
    pkgs.runCommand "pi-headroom-providers-contract" { nativeBuildInputs = [ pkgs.nodejs_24 ]; }
      ''
        node ${../tests/pi/headroom-providers-contract.mjs} ${contractJSON}
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
        node tests/pi/headroom-providers.mjs ${pkgs.python3.interpreter} ${lib.getExe base.config.local.headroom.package} \
          ${lib.getExe pkgs.pi-coding-agent} ${
            pkgs.callPackage ../packages/headroom-tokenizer-cache.nix { }
          }
        touch "$out"
      '';
}
