# hosts/razer14/custom-configuration.nix
# Razer Blade 14 specific customizations
{
  config,
  pkgs,
  lib,
  ...
}:

{

  # ============================================================================
  # Module Options
  # ============================================================================
  within.cosmic.enable = true;
  within.cuda.enable = true;
  within.powertop.enable = true;
  within.mullvad.enable = true;
  within.steam.enable = true;
  within.docker.enable = true;
  within.docker.users = [ "adriel" ];
  within.kanata.enable = true;
  within.kanata.devices = [
    "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
  ];
  within.kanata.extraGroups = [ "openrazer" ];

  # ============================================================================
  # Memory / Swap Configuration
  # ============================================================================
  # zram with writeback to dedicated partition for cold/incompressible pages
  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 100;
    writebackDevice = "/dev/disk/by-partlabel/writeback";
  };

  # Proactive OOM handling - kills cgroups gracefully before system locks up
  systemd.oomd = {
    enable = true;
    enableRootSlice = true;
    enableUserSlices = true;
  };

  # Faster initrd decompression (better than default gzip)
  boot.initrd.compressor = "zstd";

  boot.kernel.sysctl = {
    # Aggressively use zram (compressed RAM) over file cache
    "vm.swappiness" = 180;

    # Keep directory/inode caches longer (helps git, compilation)
    "vm.vfs_cache_pressure" = 50;

    # Battery: defer writes to let NVMe sleep longer (default 500 = 5s)
    "vm.dirty_writeback_centisecs" = 1500; # 15 seconds

    # Balance between RAM usage and write frequency
    "vm.dirty_background_ratio" = 10;
    "vm.dirty_ratio" = 40;

    # BBR TCP congestion control (better throughput and latency)
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";

    # Larger UDP buffers for VPN throughput (Mullvad/WireGuard)
    "net.core.rmem_max" = 2500000;
    "net.core.wmem_max" = 2500000;
  };

  # NVMe: use 'none' scheduler (hardware handles queuing)
  services.udev.extraRules = ''
    ACTION=="add|change", KERNEL=="nvme[0-9]*", ATTR{queue/scheduler}="none"
  '';

  # Prevent logs from eating disk space
  services.journald.extraConfig = ''
    SystemMaxUse=500M
    RuntimeMaxUse=100M
  '';

  # Disable core dumps (saves space unless you debug C crashes)
  systemd.coredump.enable = false;

  # ============================================================================
  # Power Management
  # ============================================================================
  services.power-profiles-daemon.enable = true;
  services.upower = {
    enable = true;
    percentageLow = 50;
  };

  # ============================================================================
  # Packages
  # ============================================================================
  users.users.adriel.packages = lib.mkDefault [
    pkgs.vim
    pkgs.alsa-tools
    pkgs.home-manager
  ];

  environment.systemPackages = with pkgs; [
    zig
    alsa-tools
    i2c-tools
    cmake
    python3
    polychromatic
  ];

  # ============================================================================
  # NVIDIA + AMD Configuration
  # ============================================================================
  services.xserver.videoDrivers = [
    "amdgpu"
    "nvidia"
  ];

  # Firmware for AMD CPU/GPU, WiFi, Bluetooth, etc.
  hardware.enableRedistributableFirmware = true;

  # Enable AMD iGPU in initrd for early KMS (smoother boot)
  hardware.amdgpu.initrd.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    open = true;
    nvidiaSettings = true;
    package = config.boot.kernelPackages.nvidiaPackages.beta;
  };

  hardware.nvidia.prime = {
    # Bus IDs from: nix shell nixpkgs#pciutils -c lspci -d ::03xx
    # c4:00.0 - NVIDIA GeForce RTX 5060 Max-Q
    # c5:00.0 - AMD Radeon 880M / 890M
    offload.enable = true;
    offload.enableOffloadCmd = true;
    amdgpuBusId = "PCI:197:0:0";
    nvidiaBusId = "PCI:196:0:0";
  };

  # ============================================================================
  # Razer Specific hardware Configuration
  # ============================================================================
  # OpenRazer for RGB control - keyStatistics disabled to prevent conflict with kanata
  hardware.openrazer = {
    enable = true;
    keyStatistics = false;
    users = [ "adriel" ];
  };

  # ============================================================================
  # Networking
  # ============================================================================
  networking.extraHosts = ''
    192.168.4.27 plex-nix
  '';

  # Disable WiFi power save (MT7925 drops connections with power save enabled)
  networking.networkmanager.wifi.powersave = false;

  # ============================================================================
  # Security
  # ============================================================================
  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';
}
