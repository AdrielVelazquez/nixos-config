# modules/services/solaar.nix
{ lib, config, ... }:

let
  cfg = config.local.solaar;
in
{
  options.local.solaar.enable = lib.mkEnableOption "Enables Solaar for Logitech devices";

  config = lib.mkIf cfg.enable {
    services.solaar.enable = true;
  };
}
