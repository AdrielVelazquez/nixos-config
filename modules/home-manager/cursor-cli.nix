{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.cursor-cli;
in
{
  options.local.cursor-cli = {
    enable = lib.mkEnableOption "Cursor CLI";
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ pkgs.cursor-cli ];

    local.ai-cli-skills = {
      enable = true;
      targets.cursor = true;
    };
  };
}
