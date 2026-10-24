{
  config,
  lib,
  inputs,
  ...
}:
{
  options.local.pi.workflow.enable =
    lib.mkEnableOption "Pi Superpowers and durable project-learning skills"
    // {
      default = true;
      example = false;
    };
  config = lib.mkIf (config.local.pi.enable && config.local.pi.workflow.enable) {
    local.pi.extraSettings = {
      extensions = [ "${inputs.superpowers}/.pi/extensions/superpowers.ts" ];
      skills = [
        "${inputs.compound-engineering}/skills/ce-compound"
        "${inputs.compound-engineering}/skills/ce-compound-refresh"
      ];
    };
    programs.pi-coding-agent.context = builtins.readFile ../../../dotfiles/pi/AGENTS.md;
  };
}
