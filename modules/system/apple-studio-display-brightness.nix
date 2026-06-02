# Apple Studio Display brightness support via asdbctl.
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.apple-studio-display-brightness;
in
{
  options.local.apple-studio-display-brightness.enable = lib.mkEnableOption "Apple Studio Display brightness control";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.asdbctl ];
    services.udev.packages = [ pkgs.asdbctl ];
  };
}
