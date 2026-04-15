{
  lib,
  config,
  ...
}:

let
  cfg = config.local.yazi;
in
{
  options.local.yazi = {
    enable = lib.mkEnableOption "yazi terminal file manager";
  };

  config = lib.mkIf cfg.enable {
    programs.yazi = {
      enable = true;
      shellWrapperName = "yy";
    };
  };
}
