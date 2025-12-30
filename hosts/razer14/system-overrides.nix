# hosts/razer14/system-overrides.nix
# Razer Blade 14 system configuration overrides
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
  local.cosmic.enable = true;
  local.cuda.enable = true;
  local.powertop.enable = true;
  local.mullvad.enable = true;
  local.steam.enable = true;
  local.docker.enable = true;
  local.docker.users = [ "adriel" ];
  local.kanata.enable = true;
  local.kanata.devices = [
    "/dev/input/by-id/usb-Razer_Razer_Blade-event-kbd"
    "/dev/input/by-id/usb-Razer_Razer_Blade-if01-event-kbd"
  ];
  local.kanata.extraGroups = [ "openrazer" ];
  local.mediatek-wifi.enable = true;
  local.mediatek-wifi.useIwd = true;

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

  # Fix audio popping - disable power save on HDA Intel codec
  boot.extraModprobeConfig = lib.mkAfter ''
    options snd_hda_intel power_save=0
  '';

  boot.kernel.sysctl = {
    # Aggressively use zram (compressed RAM) over file cache
    "vm.swappiness" = 180;

    # zram optimization: read 1 page at a time (no seek penalty, less decompression)
    "vm.page-cluster" = 0;

    # Keep directory/inode caches longer (helps git, compilation)
    "vm.vfs_cache_pressure" = 50;

    # Increase max memory map areas - required by some Proton games and Electron apps
    # Default is 65530; max safe value for demanding games/apps
    "vm.max_map_count" = 2147483642;

    # BBR TCP congestion control (better throughput and latency)
    "net.core.default_qdisc" = "fq";
    "net.ipv4.tcp_congestion_control" = "bbr";

    # Larger UDP buffers for VPN throughput (Mullvad/WireGuard)
    "net.core.rmem_max" = 2500000;
    "net.core.wmem_max" = 2500000;
  };

  # Kernel params for power savings
  boot.kernelParams = [
    # Disable all watchdog timers (allows deeper C-states, saves ~0.5W)
    "nowatchdog"
  ];

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
  # System Performance
  # ============================================================================
  # High-performance D-Bus broker (lower IPC latency, used by Fedora/Arch)
  services.dbus.implementation = "broker";

  # ============================================================================
  # Power Management (extends laptop profile defaults)
  # ============================================================================
  # fwupd, fstrim, power-profiles-daemon, tmpfs already enabled by laptop profile
  services.upower = {
    percentageLow = 15; # Warn at 15% battery
    percentageCritical = 5;
    percentageAction = 3; # Hibernate at 3%
  };

  # ============================================================================
  # Packages (acpi, pciutils, powertop already in laptop profile)
  # ============================================================================
  environment.systemPackages = with pkgs; [
    zig
    alsa-tools
    i2c-tools
    cmake
    python3
    polychromatic
  ];

  programs.localsend.enable = true;
  # ============================================================================
  # NVIDIA + AMD Configuration
  # ============================================================================
  services.xserver.videoDrivers = [
    "amdgpu"
    "nvidia"
  ];

  # Firmware for AMD CPU/GPU, WiFi, Bluetooth, etc.
  hardware.enableAllFirmware = true;
  hardware.cpu.amd.updateMicrocode = true;

  # Enable AMD iGPU in initrd for early KMS (smoother boot)
  hardware.amdgpu.initrd.enable = true;

  hardware.nvidia = {
    modesetting.enable = true;
    powerManagement.enable = true;
    powerManagement.finegrained = true;
    # Allow GPU to fully power off (D3cold) when idle - critical for battery
    nvidiaPersistenced = false;
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

  # ============================================================================
  # WiFi Networks (declarative with SOPS secrets)
  # ============================================================================
  local.wifi-profiles.cotu.enable = true;
  local.wifi-profiles.reddit-guest.enable = true;

  # ============================================================================
  # Security
  # ============================================================================
  security.sudo.extraConfig = ''
    Defaults env_keep += "SSH_AUTH_SOCK"
  '';

}
