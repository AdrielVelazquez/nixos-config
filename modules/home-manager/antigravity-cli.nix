{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.antigravity-cli;
in
{
  options.local.antigravity-cli.enable = lib.mkEnableOption "Antigravity CLI";

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.antigravity-cli ];

    local.ai-cli-skills = {
      enable = true;
      targets.antigravity = true;
    };
  };
}
