{
  lib,
  config,
  ...
}:

with lib;

let
  cfg = config.within.solaar;
in
{
  options.within.solaar.enable = mkEnableOption "Enables solaar Settings";

  config = mkIf cfg.enable {
    services.solaar.enable = true;
  };
}
