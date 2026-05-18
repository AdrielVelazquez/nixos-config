{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.codex-cli;
in
{
  options.local.codex-cli = {
    enable = lib.mkEnableOption "Codex CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.codex ];

    local.ai-cli-skills = {
      enable = true;
      targets.codex = true;
    };
  };
}
