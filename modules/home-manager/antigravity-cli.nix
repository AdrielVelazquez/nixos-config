{
  lib,
  config,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.local.antigravity-cli;
  headroomCfg = config.local.headroom;
  headroomEnabled = headroomCfg.enable && (headroomCfg.agents.antigravity or false);

  antigravityPkgs = import inputs.nixpkgs-antigravity {
    system = pkgs.stdenv.hostPlatform.system;
    config.allowUnfree = true;
  };

  antigravityPackage =
    if headroomEnabled then
      pkgs.writeShellScriptBin "agy" ''
        export ANTHROPIC_BASE_URL="${headroomCfg.proxyUrl}"
        export OPENAI_BASE_URL="${headroomCfg.proxyBaseUrl}"
        exec ${headroomCfg.sessionHelper}/bin/headroom-agent-session antigravity -- ${antigravityPkgs.antigravity-cli}/bin/agy "$@"
      ''
    else
      antigravityPkgs.antigravity-cli;
in
{
  options.local.antigravity-cli = {
    enable = lib.mkEnableOption "Antigravity CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ (lib.hiPrio antigravityPackage) ];

    local.ai-cli-skills = {
      enable = true;
      targets.antigravity = true;
    };
  };
}
