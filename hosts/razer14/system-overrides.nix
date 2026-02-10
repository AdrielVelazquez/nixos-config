# hosts/razer14/system-overrides.nix
{
  config,
  pkgs,
  lib,
  ...
}:

{
  local.cosmic.enable = true;
  local.cuda.enable = true;
  local.mullvad.enable = true;
  local.steam.enable = true;
  local.docker.enable = true;
  local.docker.users = [ "adriel" ];
  local.kanata.enable = true;
  # Runtime layer switching: hold backtick + 1 (Colemak-DH) or 2 (Gallium)
  local.kanata.devices = [
    "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
  ];
  local.kanata.extraGroups = [ "openrazer" ];
  local.mediatek-wifi.enable = true;
  local.mediatek-wifi.useIwd = true;
  local.zsa-keyboard.enable = true;
  local.zsa-keyboard.users = [ "adriel" ];

  nix.daemonCPUSchedPolicy = "idle";
  nix.daemonIOSchedClass = "idle";

  # NOTE: Removed powerManagement.powertop.enable - conflicts with power-profiles-daemon
  # PPD is enabled in laptop.nix and integrates with COSMIC's power slider
  # powertop package is still available for diagnostics (in laptop.nix)

  # 64GB RAM: 50% zram cap prevents thrashing, writeback for cold pages
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 50;
    writebackDevice = "/dev/disk/by-partlabel/writeback";
  };

  services.earlyoom = {
    enable = true;
    enableNotifications = true;
    freeMemThreshold = 5;
    freeSwapThreshold = 5;
  };

  boot.initrd.compressor = "zstd";
  boot.tmp.tmpfsSize = "32G";

  # Audio power management - 10 second timeout before codec sleeps
  # If you hear pops when audio resumes, change back to power_save=0
  boot.extraModprobeConfig = lib.mkAfter ''
    options snd_hda_intel power_save=10
  '';

  boot.kernel.sysctl = {
    # -----------------------------------------------------------------------
    # MEMORY & ZRAM TUNING
    # -----------------------------------------------------------------------
    "vm.swappiness" = 100;
    # 0 is required for ZRAM (disables read-ahead to save CPU).
    "vm.page-cluster" = 0;

    # -----------------------------------------------------------------------
    # WRITEBACK TUNING (Fixed for 64GB RAM)
    # -----------------------------------------------------------------------

    # Start writing to disk immediately in the background (256MB).
    # Keeps the "pipe" moving so the buffer rarely fills up.
    "vm.dirty_background_bytes" = 268435456;

    # Force application pause at 1GB.
    "vm.dirty_bytes" = 1073741824;

    # Timeout for dirty data (power saving)
    "vm.dirty_expire_centisecs" = 3000; # 30s
    "vm.dirty_writeback_centisecs" = 1500; # 15s
    "vm.laptop_mode" = 5;

    # -----------------------------------------------------------------------
    # FILESYSTEM & CACHE
    # -----------------------------------------------------------------------
    # Keep directory structure in RAM longer (makes 'ls' and 'find' snappy)
    "vm.vfs_cache_pressure" = 30;

    # Essential for gaming (Proton/Wine) and heavy apps (ES/Kafka)
    "vm.max_map_count" = 2147483642;

    # Increase file watchers for VS Code / IDEs
    "fs.inotify.max_user_watches" = 524288;
    "fs.inotify.max_user_instances" = 1024;
    "fs.file-max" = 2097152;

    # -----------------------------------------------------------------------
    # NETWORK (BBR + Optimization)
    # -----------------------------------------------------------------------
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";
    "net.core.rmem_max" = 2500000;
    "net.core.wmem_max" = 2500000;
    "net.ipv4.tcp_fastopen" = 3;
  };

  boot.kernelParams = [
    "nowatchdog"
    # AMD GPU power efficiency
    "amdgpu.freesync_video=1" # VRR for video playback (match frame rate)
    "amdgpu.dcfeaturemask=0x3" # PSR (Panel Self Refresh) + ABM
    "amdgpu.abmlevel=2" # Adaptive Backlight Management (1-4, higher = more savings, 2 = balanced)
    "amdgpu.runpm=-1" # Runtime PM with display support (GPU can sleep when idle)
  ];

  services.udev.extraRules = ''
    # NVMe Optimization: Disable kernel scheduler (latency/CPU win)
    ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"

    # PCIe ASPM Power Management
    # Battery: Aggressive (L1 substates enabled). Saves ~1-2W.
    ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="0", \
      RUN+="${pkgs.bash}/bin/sh -c 'echo powersupersave > /sys/module/pcie_aspm/parameters/policy'"

    # AC Power: Moderate (L0s/L1 enabled). Keeps laptop cool but responsive.
    # (If you get lag in games on AC, change 'powersave' to 'performance')
    ACTION=="add|change", SUBSYSTEM=="power_supply", ATTR{type}=="Mains", ATTR{online}=="1", \
      RUN+="${pkgs.bash}/bin/sh -c 'echo powersave > /sys/module/pcie_aspm/parameters/policy'"
  '';

  services.journald.extraConfig = ''
    SystemMaxUse=500M
    RuntimeMaxUse=100M
  '';

  systemd.coredump.enable = false;
  services.dbus.implementation = "broker";

  services.upower = {
    percentageLow = 15;
    percentageCritical = 5;
    percentageAction = 3;
  };

  environment.systemPackages = with pkgs; [
    zig
    alsa-tools
    i2c-tools
    cmake
    python3
    polychromatic
  ];

  programs.localsend.enable = true;

  services.xserver.videoDrivers = [
    "amdgpu"
    "nvidia"
  ];
  hardware.enableAllFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;
  hardware.amdgpu.initrd.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    nvidiaPersistenced = false; # Allow D3cold for battery
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  hardware.nvidia.prime = {
    offload.enable = true;
    offload.enableOffloadCmd = true;
    amdgpuBusId = "PCI:197:0:0";
    nvidiaBusId = "PCI:196:0:0";
  };

  # OpenRazer: keyStatistics disabled to prevent conflict with kanata
  hardware.openrazer = {
    enable = true;
    keyStatistics = false;
    users = [ "adriel" ];
  };

  networking.extraHosts = ''
    192.168.4.27 plex-nix
  '';

  local.wifi-profiles.cotu.enable = true;
  local.wifi-profiles.reddit-guest.enable = true;

  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';
}
