{
  config,
  lib,
  ...
}:
let
  cfg = config.local.endpoint-agent-limits;
  baseline = {
    CPUAccounting = true;
    CPUWeight = 1;
    CPUQuota = "0.25%";
    MemoryAccounting = true;
    MemoryHigh = "40M";
    MemoryMax = "48M";
    MemorySwapMax = "0";
  };
  dropIn = settings: {
    overrideStrategy = "asDropin";
    text = lib.generators.toINI { } { Service = settings; };
  };
in
{
  options.local.endpoint-agent-limits.enable = lib.mkEnableOption "native endpoint-agent resource limits";

  config = lib.mkIf cfg.enable {
    systemd.services.orbit = lib.mkIf config.services.orbit.enable {
      serviceConfig = baseline // {
        CPUWeight = 100;
        CPUQuota = "20%";
        MemoryHigh = "480M";
        MemoryMax = "500M";
      };
    };
    systemd.services.cloudflare-warp = lib.mkIf config.services.cloudflare-warp.enable {
      serviceConfig = (builtins.removeAttrs baseline [ "CPUQuota" ]) // {
        CPUWeight = 100;
        MemoryHigh = "512M";
        MemoryMax = "1G";
        MemorySwapMax = "256M";
      };
    };

    # These are only drop-ins, not substitute units for the separately deployed agents.
    systemd.units = {
      "falcon-sensor.service" = dropIn (
        baseline
        // {
          CPUWeight = 10;
          CPUQuota = "5%";
          MemoryHigh = "256M";
          MemoryMax = "512M";
        }
      );
      "duo-desktop.service" = dropIn (
        baseline
        // {
          MemoryHigh = "80M";
          MemoryMax = "96M";
        }
      );
    };
    systemd.user.units."warp-taskbar.service" = dropIn (
      baseline
      // {
        CPUQuota = "1%";
        MemoryHigh = "48M";
        MemoryMax = "64M";
      }
    );
  };
}
