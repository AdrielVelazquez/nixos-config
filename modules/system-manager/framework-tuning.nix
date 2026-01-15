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

    audioPowerSave = lib.mkOption {
      type = lib.types.int;
      default = 10;
      description = "Audio power save timeout in seconds (0 to disable, prevents pops)";
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

    # Audio power management - prevents codec from sleeping too aggressively
    # Set audioPowerSave = 0 if you hear pops when audio resumes
    environment.etc."modprobe.d/99-audio-powersave.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      options snd_hda_intel power_save=${toString cfg.audioPowerSave}
    '';

    # Zen Browser/Firefox environment variables to prevent GPU context loss after suspend
    # systemd environment.d files are loaded by systemd and available to all user sessions
    environment.etc."environment.d/99-zen-browser.conf".text = ''
      # MANAGED BY SYSTEM-MANAGER
      # Zen Browser/Firefox environment variables to prevent GPU context loss after suspend
      MOZ_DISABLE_RDD_SANDBOX=1
      MOZ_ENABLE_WAYLAND=1
      MOZ_GPU_PROCESS_CRASH_TIMEOUT=60000
      MOZ_DISABLE_GPU_SANDBOX=1
    '';
  };
}
