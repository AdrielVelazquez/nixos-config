# modules/home-manager/niri/walker.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.niri;
in
{
  options.local.niri.walker.enable = lib.mkEnableOption "Walker application launcher";

  config = lib.mkIf (cfg.enable && cfg.walker.enable) {
    programs.walker = {
      enable = true;
      runAsService = false;
      config = {
        providers = {
          default = [
            "windows"
            "desktopapplications"
            "calc"
            "websearch"
          ];
          empty = [
            "desktopapplications"
            "windows"
          ];
        };
      };
    };
  };
}
