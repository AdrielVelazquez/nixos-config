{
  lib,
  config,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.within.kubectl;
in
{
  options.within.kubectl.enable = mkEnableOption "Enables Within's kubectl config";

  config = mkIf cfg.enable {
    home.packages = [
      pkgs.kubectl
    ];
  };
}
