# Resource-control drop-ins for vendor-owned endpoint background agents.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.endpoint-agent-limits;

  resourceDropIn =
    {
      cpuWeight,
      cpuQuota,
      memoryHigh,
      memoryMax,
      memorySwapMax,
    }:
    ''
      [Service]
      CPUAccounting=yes
      CPUWeight=${toString cpuWeight}
      CPUQuota=${cpuQuota}
      MemoryAccounting=yes
      MemoryHigh=${memoryHigh}
      MemoryMax=${memoryMax}
      MemorySwapMax=${memorySwapMax}
    '';
in
{
  options.local.endpoint-agent-limits.enable = lib.mkEnableOption "resource limits for endpoint background agents";

  config = lib.mkIf cfg.enable {
    environment.etc."systemd/system/warp-svc.service.d/50-resource-limits.conf".text = resourceDropIn {
      cpuWeight = 20;
      cpuQuota = "20%";
      memoryHigh = "512M";
      memoryMax = "1G";
      memorySwapMax = "256M";
    };

    environment.etc."systemd/system/orbit.service.d/50-resource-limits.conf".text = resourceDropIn {
      cpuWeight = 20;
      cpuQuota = "20%";
      memoryHigh = "256M";
      memoryMax = "512M";
      memorySwapMax = "256M";
    };

    environment.etc."systemd/system/duo-desktop.service.d/50-resource-limits.conf".text =
      resourceDropIn
        {
          cpuWeight = 20;
          cpuQuota = "20%";
          memoryHigh = "256M";
          memoryMax = "512M";
          memorySwapMax = "256M";
        };
  };
}
