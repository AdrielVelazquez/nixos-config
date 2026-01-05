# modules/profiles/laptop.nix
{ lib, pkgs, ... }:

{
  imports = [
    ./desktop.nix
  ];

  services.upower.enable = lib.mkDefault true;
  services.power-profiles-daemon.enable = lib.mkDefault true;
  services.fwupd.enable = lib.mkDefault true;
  services.fstrim.enable = lib.mkDefault true;
  boot.tmp.useTmpfs = lib.mkDefault true;

  boot.kernelParams = lib.mkDefault [
    "pcie_aspm=powersave"
    "workqueue.power_efficient=1"
  ];

  boot.kernel.sysctl = {
    # Saves ~0.5W
    "kernel.nmi_watchdog" = lib.mkDefault 0;
    # Batch writes to let NVMe sleep longer
    "vm.laptop_mode" = lib.mkDefault 5;
    "vm.dirty_writeback_centisecs" = lib.mkDefault 1500;
    "vm.dirty_background_ratio" = lib.mkDefault 10;
    "vm.dirty_ratio" = lib.mkDefault 40;
  };

  environment.systemPackages = with pkgs; [
    acpi
    powertop
    pciutils
  ];
}
