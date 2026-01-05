# modules/system-manager/framework-tuning.nix
{
  lib,
  config,
  ...
}:

let
  cfg = config.local.framework-tuning;
in
{
  options.local.framework-tuning = {
    enable = lib.mkEnableOption "Framework laptop system tuning";

    ramGB = lib.mkOption {
      type = lib.types.int;
      default = 32;
      description = "RAM size in GB (affects swappiness and dirty ratios)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc."sysctl.d/99-framework-tuning.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      vm.swappiness = 100
      vm.vfs_cache_pressure = 30
      vm.dirty_ratio = 15
      vm.dirty_background_ratio = 5
      vm.dirty_expire_centisecs = 3000
      vm.dirty_writeback_centisecs = 1500
      vm.laptop_mode = 5
      vm.page-cluster = 0

      net.core.default_qdisc = fq
      net.ipv4.tcp_congestion_control = bbr
      net.ipv4.tcp_fastopen = 3
      net.core.rmem_max = 2500000
      net.core.wmem_max = 2500000

      fs.inotify.max_user_watches = 524288
      fs.inotify.max_user_instances = 1024
      fs.file-max = 2097152
    '';

    environment.etc."udev/rules.d/99-nvme-scheduler.rules".text = ''
      # MANAGED BY SYSTEM-MANAGER
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
    '';

    environment.etc."systemd/journald.conf.d/99-framework-tuning.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      [Journal]
      SystemMaxUse=500M
      RuntimeMaxUse=100M
    '';
  };
}
