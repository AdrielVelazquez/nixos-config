# hosts/razer14/hardware-configuration.nix
# This version uses partition labels - portable across reinstalls!
# See README.md for required partition labels when reinstalling.
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "rtsx_pci_sdmmc"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # LUKS encrypted devices - referenced by partition label (not UUID)
  boot.initrd.luks.devices = {
    cryptroot = {
      device = "/dev/disk/by-partlabel/root";
      preLVM = true;
    };
    cryptswap = {
      device = "/dev/disk/by-partlabel/swap";
    };
  };

  # Root filesystem - uses the opened LUKS mapper name
  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "ext4";
  };

  # Boot partition - can use either partition label or filesystem label
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/RAZER-BOOT";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Swap - uses the opened LUKS mapper name
  swapDevices = [
    { device = "/dev/mapper/cryptswap"; }
  ];

  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
}
