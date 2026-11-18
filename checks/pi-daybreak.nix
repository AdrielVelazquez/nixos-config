{
  lib,
  pkgs,
  checkSources,
  homeConfigurations,
  razerHome,
  ...
}:
let
  framework = homeConfigurations.cachyos-framework13.config;
  entry = framework.local.pi.daybreak.entries.daybreak;
  isDaybreak = path: lib.hasInfix "openai-daybreak-blue" (toString path);
in
assert framework.local.pi.daybreak.enable;
assert lib.elem entry framework.programs.pi-coding-agent.settings.extensions;
assert !lib.any isDaybreak razerHome.programs.pi-coding-agent.settings.extensions;
{
  pi-daybreak =
    pkgs.runCommand "pi-daybreak-check"
      {
        nativeBuildInputs = [ pkgs.nodejs_24 ];
      }
      ''
        test -f ${entry}
        grep -Fq 'openai-daybreak-blue.ts' ${entry}
        cd ${checkSources.pi-daybreak}
        node --test tests/pi/openai-daybreak-blue-core.test.mjs tests/pi/openai-daybreak-blue.test.mjs
        touch "$out"
      '';
}
