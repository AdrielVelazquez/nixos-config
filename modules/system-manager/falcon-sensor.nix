# modules/system-manager/falcon-sensor.nix
#
# Resource-control drop-in for the vendor-owned CrowdStrike Falcon unit.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.falcon-sensor;
in
{
  options.local.falcon-sensor = {
    enable = lib.mkEnableOption "CrowdStrike Falcon Sensor resource limits";

    cpuWeight = lib.mkOption {
      type = lib.types.ints.between 1 10000;
      default = 5;
      description = "Relative CPU scheduling weight for falcon-sensor.service.";
    };

    cpuQuota = lib.mkOption {
      type = lib.types.str;
      default = "10%";
      description = "Hard CPU quota for falcon-sensor.service.";
    };

    memoryHigh = lib.mkOption {
      type = lib.types.str;
      default = "500M";
      description = "Soft memory pressure threshold for falcon-sensor.service.";
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "Hard memory limit for falcon-sensor.service.";
    };

    memorySwapMax = lib.mkOption {
      type = lib.types.str;
      default = "512M";
      description = "Hard swap limit for falcon-sensor.service.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."systemd/system/falcon-sensor.service.d/50-resource-limits.conf".text = ''
      [Service]
      CPUAccounting=yes
      CPUWeight=${toString cfg.cpuWeight}
      CPUQuota=${cfg.cpuQuota}
      MemoryAccounting=yes
      MemoryHigh=${cfg.memoryHigh}
      MemoryMax=${cfg.memoryMax}
      MemorySwapMax=${cfg.memorySwapMax}
    '';
  };
}
