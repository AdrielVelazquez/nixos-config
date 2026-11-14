{
  lib,
  pkgs,
  razerHome,
  checkSources,
  ...
}:
let
  usage = razerHome.local.pi.goUsage;
  settings = razerHome.programs.pi-coding-agent.settings;
  keyFile = razerHome.sops.secrets.${razerHome.local.pi.apiKeys."opencode-go"}.path;
in
assert usage.enable;
assert lib.elem usage.entries.usage settings.extensions;
{
  pi-opencode-go-usage =
    pkgs.runCommand "pi-opencode-go-usage-check"
      {
        nativeBuildInputs = [ pkgs.nodejs_24 ];
      }
      ''
        test -f ${usage.entries.usage}
        grep -Fq 'createOpenCodeGoUsage' ${usage.entries.usage}
        grep -Fq ${lib.escapeShellArg keyFile} ${usage.entries.usage}
        cd ${checkSources.pi-opencode-go-usage}
        node --test tests/pi/opencode-go-usage.test.mjs
        touch "$out"
      '';
}
