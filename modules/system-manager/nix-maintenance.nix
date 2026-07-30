{
  config,
  lib,
  ...
}:

let
  cfg = config.local.nix-maintenance;
  maintenanceServiceConfig = {
    Type = "oneshot";
    Nice = 19;
    CPUSchedulingPolicy = "idle";
    IOSchedulingClass = "idle";
  };
  maintenanceTimerConfig = {
    Persistent = cfg.persistent;
    RandomizedDelaySec = cfg.randomizedDelaySec;
  };
in
{
  options.local.nix-maintenance = {
    enable = lib.mkEnableOption "periodic Nix garbage collection and store optimisation";

    gc = {
      dates = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ "Sun *-*-* 03:00:00" ];
        description = "systemd calendar schedules for Nix garbage collection.";
      };

      deleteOlderThanDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 14;
        description = "Age in days after which old profile generations are deleted.";
      };
    };

    optimise.dates = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "Sun *-*-* 05:00:00" ];
      description = "systemd calendar schedules for Nix store optimisation.";
    };

    persistent = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether missed maintenance timers run after the next boot.";
    };

    randomizedDelaySec = lib.mkOption {
      type = lib.types.str;
      default = "1h";
      description = "Random delay applied to each maintenance timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.nix-gc = {
      description = "Garbage Collect Nix Store";
      startAt = cfg.gc.dates;
      serviceConfig = maintenanceServiceConfig;
      script = ''
        ${lib.getExe' config.nix.package "nix-collect-garbage"} --delete-older-than ${toString cfg.gc.deleteOlderThanDays}d
      '';
    };

    systemd.services.nix-optimise = {
      description = "Optimise Nix Store";
      startAt = cfg.optimise.dates;
      serviceConfig = maintenanceServiceConfig;
      script = ''
        ${lib.getExe' config.nix.package "nix-store"} --optimise
      '';
    };

    systemd.timers.nix-gc.timerConfig = maintenanceTimerConfig;
    systemd.timers.nix-optimise.timerConfig = maintenanceTimerConfig;
  };
}
