# modules/system-manager/framework-tuning.nix
# System tuning for Framework laptop (or any non-NixOS Linux)
# Similar optimizations to the Razer Blade 14 config
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
    # =========================================================================
    # Sysctl tuning - kernel parameters
    # =========================================================================
    environment.etc."sysctl.d/99-framework-tuning.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER - DO NOT EDIT
      # System tuning for ${toString cfg.ramGB}GB RAM

      # ========================================
      # Memory
      # ========================================
      # Balanced swappiness - prefer RAM over swap when plentiful
      vm.swappiness = 100

      # Keep directory/inode caches longer (faster git, file ops)
      vm.vfs_cache_pressure = 30

      # Dirty page tuning - buffer more writes before flushing
      vm.dirty_ratio = 15
      vm.dirty_background_ratio = 5
      vm.dirty_expire_centisecs = 3000
      vm.dirty_writeback_centisecs = 1500

      # Laptop mode - delay disk writes for power savings
      vm.laptop_mode = 5

      # zram optimization (if zram enabled)
      vm.page-cluster = 0

      # ========================================
      # Network
      # ========================================
      # BBR TCP congestion control (better throughput and latency)
      net.core.default_qdisc = fq
      net.ipv4.tcp_congestion_control = bbr

      # TCP Fast Open - faster repeat connections
      net.ipv4.tcp_fastopen = 3

      # Larger UDP buffers for VPN throughput
      net.core.rmem_max = 2500000
      net.core.wmem_max = 2500000

      # ========================================
      # IDE/Dev
      # ========================================
      # inotify limits - prevents "too many files" in IDEs
      fs.inotify.max_user_watches = 524288
      fs.inotify.max_user_instances = 1024

      # File descriptor limits
      fs.file-max = 2097152
    '';

    # =========================================================================
    # udev rules - NVMe scheduler
    # =========================================================================
    environment.etc."udev/rules.d/99-nvme-scheduler.rules".text = ''
      # MANAGED BY SYSTEM-MANAGER - DO NOT EDIT
      # NVMe: use 'none' scheduler (hardware handles queuing)
      ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
    '';
  };
}


