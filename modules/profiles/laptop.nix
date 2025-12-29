# modules/profiles/laptop.nix
# Laptop systems - desktop + power management + battery optimizations
{ lib, pkgs, ... }:

{
  imports = [
    ./desktop.nix
  ];

  # ============================================================================
  # Power Management
  # ============================================================================
  services.upower.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;

  # ============================================================================
  # Laptop-specific Services
  # ============================================================================
  # Firmware updates
  services.fwupd.enable = lib.mkDefault true;

  # SSD health
  services.fstrim.enable = lib.mkDefault true;

  # Use RAM for /tmp (faster, reduces disk writes)
  boot.tmp.useTmpfs = lib.mkDefault true;

  # ============================================================================
  # Kernel Tuning (Battery Optimization)
  # ============================================================================
  boot.kernelParams = lib.mkDefault [
    # PCIe ASPM power saving
    "pcie_aspm=powersave"
    # Prefer power-efficient CPU scheduling
    "workqueue.power_efficient=1"
  ];

  boot.kernel.sysctl = {
    # Disable NMI watchdog (saves ~0.5W, not needed on laptops)
    "kernel.nmi_watchdog" = lib.mkDefault 0;

    # Laptop mode: batch disk writes to allow NVMe to sleep longer
    # Works with dirty_writeback_centisecs to group I/O operations
    "vm.laptop_mode" = lib.mkDefault 5;

    # Battery: defer writes to let NVMe sleep longer (default 500 = 5s)
    "vm.dirty_writeback_centisecs" = lib.mkDefault 1500; # 15 seconds

    # Balance between RAM usage and write frequency
    "vm.dirty_background_ratio" = lib.mkDefault 10;
    "vm.dirty_ratio" = lib.mkDefault 40;
  };

  # ============================================================================
  # Laptop Packages
  # ============================================================================
  environment.systemPackages = with pkgs; [
    acpi
    powertop
    pciutils
  ];
}

