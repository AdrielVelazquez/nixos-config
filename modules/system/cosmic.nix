# modules/system/cosmic.nix
{
  lib,
  config,
  pkgs,
  ...
}:

let
  cfg = config.local.cosmic;
in
{
  options.local.cosmic.enable = lib.mkEnableOption "Enables COSMIC desktop environment";

  config = lib.mkIf cfg.enable {
    # Fail build if conflicting schedulers are enabled
    assertions = [
      {
        assertion = !(config.services.ananicy.enable or false);
        message = "Cannot enable both system76-scheduler (via COSMIC) and ananicy. They conflict.";
      }
      {
        assertion = !(config.services.scx.enable or false);
        message = "Cannot enable both system76-scheduler (via COSMIC) and scx (sched_ext). They conflict.";
      }
    ];

    services.desktopManager.cosmic.enable = true;
    services.displayManager.cosmic-greeter.enable = true;

    # Exclude apps we don't use (using kitty instead)
    environment.cosmic.excludePackages = with pkgs; [
      cosmic-term
    ];

    # System76's scheduler for improved desktop responsiveness
    services.system76-scheduler.enable = true;
  };
}
