# hosts/razer14/hardware.nix
# Hardware-specific settings that disko doesn't handle
{
  config,
  lib,
  modulesPath,
  ...
}:

{
  imports = [
    (modulesPath + "/installer/scan/not-detected.nix")
  ];

  # Kernel modules for initrd
  boot.initrd.availableKernelModules = [
    "nvme"
    "xhci_pci"
    "thunderbolt"
    "usbhid"
    "rtsx_pci_sdmmc"
    "usb_storage" # USB boot support
    "sd_mod"
  ];
  boot.initrd.kernelModules = [ ];
  boot.kernelModules = [ "kvm-amd" ];
  boot.extraModulePackages = [ ];

  # Platform and CPU
  nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
  hardware.cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;

  # Swap priority - low so zram is preferred
  swapDevices = lib.mkForce [
    {
      device = "/dev/mapper/cryptswap";
      priority = 1;
    }
  ];
}
