{
  lib,
  pkgs,
  homeConfigurations,
  razerHome,
  ...
}:
let
  shared = import ./pi-managed-fixture.nix { inherit lib pkgs homeConfigurations; };
  framework = homeConfigurations.cachyos-framework13.config;
  schemas = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo/schemas";
  settingsFile =
    name: home:
    pkgs.writeText "pi-${name}-settings.json" (builtins.toJSON home.programs.pi-coding-agent.settings);
  modelsFile = home: home.home.file."${home.local.pi.agentDir}/models.json".source;
in
{
  pi-settings = pkgs.runCommand "pi-settings-check" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    export HOME="$TMPDIR/home" PI_OFFLINE=1 PI_TELEMETRY=0
    mkdir -p "$HOME" "$out"
    python3 -E ${../tests/pi/writable-settings.py} ${lib.getExe pkgs.pi-coding-agent} ${shared.contract}
  '';

  pi-hyperlinks = pkgs.runCommand "pi-hyperlinks-check" { nativeBuildInputs = [ pkgs.nodejs ]; } ''
    node ${../tests/pi/terminal-hyperlinks.mjs} ${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo \
      framework=${settingsFile "framework" framework} razer=${settingsFile "razer" razerHome}
    touch "$out"
  '';

  # What the repository generates must satisfy Pi's own schemas: a wrong type or enum value in a key Pi reads is
  # caught here instead of by a warning at the next start.
  pi-settings-schema =
    pkgs.runCommand "pi-settings-schema"
      { nativeBuildInputs = [ (pkgs.python3.withPackages (p: [ p.jsonschema ])) ]; }
      ''
        python3 -E ${../tests/pi/settings-schema.py} ${schemas}/settings.schema.json ${schemas}/models.schema.json \
          framework=${settingsFile "framework" framework} razer=${settingsFile "razer" razerHome} \
          -- razer=${modelsFile razerHome}
        touch "$out"
      '';
}
