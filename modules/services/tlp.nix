{ lib, config, ... }:

with lib;

let
  cfg = config.within.tlp;
in
{
  options.within.tlp.enable = mkEnableOption "Enables tlp Settings";

  config = mkIf cfg.enable {
    services.power-profiles-daemon.enable = false;
    services.tlp = {
      enable = true;
      settings = {
        CPU_SCALING_GOVERNOR_ON_AC = "performance";
        CPU_SCALING_GOVERNOR_ON_BAT = "powersave";

        CPU_ENERGY_PERF_POLICY_ON_BAT = "power";
        CPU_ENERGY_PERF_POLICY_ON_AC = "performance";

        CPU_BOOST_ON_AC = 1;
        CPU_BOOST_ON_BAT = 0;

        CPU_DRIVER_OPMODE_ON_AC = "guided";
        CPU_DRIVER_OPMODE_ON_BAT = "guided";

        # AMDGPU_ABM_LEVEL_ON_AC = 0;
        # AMDGPU_ABM_LEVEL_ON_BAT = 3;
      };
    };
  };
}
