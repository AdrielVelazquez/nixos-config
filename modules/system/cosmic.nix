{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.cosmic;
in
{
  options.within.cosmic.enable = mkEnableOption "Enables cosmic desktopManager";
  # cosmic does lot's of system changes, so we need to call this outside of homemanager
  config = mkIf cfg.enable {
    services.desktopManager.cosmic.enable = true;
  };
}
