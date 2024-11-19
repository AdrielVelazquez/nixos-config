{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.keyd;
in
{
  options.within.keyd.enable = mkEnableOption "Enables keyd Settings";
  config = mkIf cfg.enable {
    services.keyd = {
      enable = true;
      keyboards = {
        default = {
          ids = [ "*" ];
          settings = {
            main = {
              capslock = "overload(control, backspace)";
              t = "t & shift";
            };
          };
        };
      };
    };

  };
}
