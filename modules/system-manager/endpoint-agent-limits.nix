# Resource-control drop-ins for vendor-owned endpoint background agents.
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.endpoint-agent-limits;

  endpointDropIn = {
    cpuWeight = 1;
    cpuQuota = "0.25%";
    memoryHigh = "40M";
    memoryMax = "48M";
    memorySwapMax = "0";
  };

  duoDropIn = endpointDropIn // {
    memoryHigh = "80M";
    memoryMax = "96M";
  };

  orbitDropIn = endpointDropIn // {
    cpuWeight = 100;
    cpuQuota = "20%";
    memoryHigh = "480M";
    memoryMax = "500M";
  };

  warpSvcDropIn = endpointDropIn // {
    cpuWeight = 100;
    cpuQuota = null;
    memoryHigh = "512M";
    memoryMax = "1G";
    memorySwapMax = "256M";
  };

  warpTaskbarDropIn = endpointDropIn // {
    cpuQuota = "1%";
    memoryHigh = "48M";
    memoryMax = "64M";
  };

  resourceDropIn =
    {
      cpuWeight,
      cpuQuota ? null,
      memoryHigh,
      memoryMax,
      memorySwapMax,
    }:
    ''
      [Service]
      CPUAccounting=yes
      CPUWeight=${toString cpuWeight}
    ''
    + lib.optionalString (cpuQuota != null) ''
      CPUQuota=${cpuQuota}
    ''
    + ''
      MemoryAccounting=yes
      MemoryHigh=${memoryHigh}
      MemoryMax=${memoryMax}
      MemorySwapMax=${memorySwapMax}
    '';
in
{
  options.local.endpoint-agent-limits.enable = lib.mkEnableOption "resource limits for endpoint background agents";

  config = lib.mkIf cfg.enable {
    environment.etc."systemd/system/warp-svc.service.d/50-resource-limits.conf".text =
      resourceDropIn warpSvcDropIn;

    environment.etc."systemd/system/orbit.service.d/50-resource-limits.conf".text =
      resourceDropIn orbitDropIn;

    environment.etc."systemd/system/duo-desktop.service.d/50-resource-limits.conf".text =
      resourceDropIn duoDropIn;

    environment.etc."systemd/user/warp-taskbar.service.d/50-resource-limits.conf".text =
      resourceDropIn warpTaskbarDropIn;
  };
}
